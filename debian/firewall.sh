#!/usr/bin/env bash
# Debian 13 host firewall. Run manually; run-all.sh does not enable it.
#
#   sudo ./firewall.sh --enable   install/update filtering and enable at boot
#   sudo ./firewall.sh --disable  remove ONLY this firewall's filtering
#        ./firewall.sh --status   inspect configuration (sudo also shows rules)
#   sudo ./firewall.sh --harden   separately apply kernel/module/service settings
#        ./firewall.sh --help     explain commands and current preferences
#
# --disable does NOT undo hardening or start services. The old script never
# saved enough information for an exact undo. Its original backups are retained.
# --enable migrates an old installation without stopping nftables.service or
# flushing other tables. See firewall.md before applying to another machine.
# Changing commands append their history to /var/log/untrusted-network-firewall/.
#
# This blocks unsolicited connections to the host, with control exceptions.
# Existing connections remain allowed. It does not authenticate routers/DHCP/DNS,
# encrypt traffic, prevent malicious downloads, or hide you. Local isolation is
# partial: DNS/control traffic and public destinations remain reachable, including
# neighbors with public IPv4/IPv6 addresses.

ALLOW_LOCAL_NETWORK=no
ALLOW_PRINTING=no
ALLOW_BLUETOOTH=yes

# Typical physical-interface names. Add custom names here.
# VPNs and container bridges are excluded from outbound LAN blocking.
# Host inbound filtering still covers all interfaces.
UNTRUSTED_INTERFACES=( "wl*" "en*" "eth*" "usb*" "ww*" )

set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

TABLE=untrusted_network
OWNER=untrusted-network-firewall-v2
MARKER="# Managed by debian/firewall.sh v2"
RULES_FILE=/etc/untrusted-network.nft
UNIT=untrusted-network-firewall.service
UNIT_FILE=/etc/systemd/system/untrusted-network-firewall.service
LEGACY_CONF=/etc/nftables.conf
STATE_DIR=/var/lib/untrusted-network-firewall
SYSCTL_CONF=/etc/sysctl.d/99-untrusted-network.conf
MODULE_CONF=/etc/modprobe.d/99-untrusted-network.conf
LOCK_FILE=/run/lock/untrusted-network-firewall.lock
LOG_DIR=/var/log/untrusted-network-firewall
LOG_FILE=$LOG_DIR/history.log
PRINTING_UNITS=( cups.service cups.socket cups.path cups-browsed.service avahi-daemon.service avahi-daemon.socket )
OTHER_UNITS=( NetworkManager.service ModemManager.service bluetooth.service )
work=
log_fd=
log_run_id=
log_state_ready=no

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<HELP
Usage: $0 OPTION

  --enable   Load/update firewall rules and enable them at boot.
  --disable  Remove only this firewall's rules.
  --status   Show service states and kernel settings; sudo also shows live rules.
  --harden   Configure kernel/module restrictions, services, and automatic updates.
  -h, --help Show this help without changing anything.

Use sudo for --enable, --disable, and --harden.
--disable leaves hardening and service settings in place.
Changing commands keep a private history in $LOG_FILE.
Read it with: sudo less $LOG_FILE

Preferences at the top of this script:
  ALLOW_LOCAL_NETWORK=$ALLOW_LOCAL_NETWORK
  ALLOW_PRINTING=$ALLOW_PRINTING
  ALLOW_BLUETOOTH=$ALLOW_BLUETOOTH

Run --enable after changing network or printing rules.
Run --harden to configure services and automatic security updates.
See firewall.md for details about protection, interface scope, and migration.
HELP
}

log_event() {
    local event="$1" fields=
    shift
    if [ "$#" -gt 0 ]; then printf -v fields ' %q' "$@"; fi
    TZ=UTC printf '[%(%Y-%m-%dT%H:%M:%SZ)T] run=%s %s%s\n' \
        -1 "$log_run_id" "$event" "$fields" >&"$log_fd"
}

record_state() {
    log_event STATE "$1"
    # Observation errors are recorded, never presented as an empty ruleset or
    # a successful restore. The operation performs its own mandatory checks.
    if ! show_status >&"$log_fd" 2>&1; then
        log_event STATE_INCOMPLETE "$1"
    fi
}

finish_action() {
    local result=$?
    trap - EXIT ERR HUP INT TERM
    set +e
    if [ "$log_state_ready" = yes ]; then record_state after; fi
    if [ -n "$work" ]; then rm -rf -- "$work"; fi
    exit "$result"
}

run_logged() {
    local action="$1" result
    local pipeline_status=()
    # Keep log creation inside a private directory. Never append through a
    # symlink or hard link, or take ownership of someone else's log location.
    if [ ! -e "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ]; then mkdir -m 700 "$LOG_DIR"; fi
    [ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ] ||
        die "unsafe log directory: $LOG_DIR"
    chmod 700 "$LOG_DIR"
    [ ! -L "$LOG_FILE" ] || die "refusing symlink log: $LOG_FILE"
    if [ -e "$LOG_FILE" ]; then
        [ -f "$LOG_FILE" ] && [ -O "$LOG_FILE" ] && [ "$(stat -c '%h' "$LOG_FILE")" = 1 ] ||
            die "unsafe log file: $LOG_FILE"
    fi
    exec {log_fd}>>"$LOG_FILE" || die "cannot open history: $LOG_FILE"
    chmod 600 "$LOG_FILE"
    log_run_id="${EPOCHREALTIME}-$$"
    log_event BEGIN "$action" "user=${SUDO_USER:-${USER:-unknown}}" "uid=${SUDO_UID:-$(id -u)}" ||
        die "cannot write history: $LOG_FILE"
    log_event PREFERENCES "ALLOW_LOCAL_NETWORK=$ALLOW_LOCAL_NETWORK" \
        "ALLOW_PRINTING=$ALLOW_PRINTING" "ALLOW_BLUETOOTH=$ALLOW_BLUETOOTH" \
        "UNTRUSTED_INTERFACES=${UNTRUSTED_INTERFACES[*]}"
    log_event SCRIPT "$(sha256sum -- "${BASH_SOURCE[0]}")"
    printf 'history     %s (run %s)\n' "$LOG_FILE" "$log_run_id"
    # A real pipeline waits for the log writer. Keep errexit enabled inside the
    # operation, and preserve its exit status instead of returning tee's status.
    set +e
    (
        set -Ee
        trap 'log_event ERROR "exit=$?" "line=$LINENO" "$BASH_COMMAND"' ERR
        trap finish_action EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        BASH_XTRACEFD=$log_fd
        PS4='+ ${EPOCHREALTIME} run=${log_run_id} ${BASH_SOURCE##*/}:${LINENO}: '
        set -x
        run_action "$action"
    ) 2>&1 | tee --output-error=warn -a "$LOG_FILE"
    pipeline_status=( "${PIPESTATUS[@]}" )
    set -e
    result="${pipeline_status[0]}"
    if [ "${pipeline_status[1]}" -ne 0 ]; then
        printf 'error: history output failed; the operation may have made changes\n' >&2
        if [ "$result" -eq 0 ]; then result=1; fi
    fi
    if ! log_event END "$action" "exit=$result" "output_exit=${pipeline_status[1]}"; then
        printf 'error: could not finish history; the operation may have made changes\n' >&2
        if [ "$result" -eq 0 ]; then result=1; fi
    fi
    exec {log_fd}>&-
    log_fd=
    return "$result"
}

legacy_file() {
    [ -f "$1" ] && grep -Eq '^# Written by debian(-new)?/firewall\.sh --enable$' "$1"
}

owned_path() {
    [ ! -L "$1" ] || die "refusing to replace symlink: $1"
    if [ -e "$1" ]; then
        [ -f "$1" ] || die "not a regular file: $1"
        grep -Fxq "$MARKER" "$1" || legacy_file "$1" ||
            die "refusing to change a file not owned by this script: $1"
    fi
}

atomic_install() {
    local source="$1" target="$2" mode="${3:-644}" staging
    if [ -n "$log_fd" ]; then
        log_event FILE_BEFORE "$target"
        if [ -e "$target" ]; then cat -- "$target" >&"$log_fd"; else log_event ABSENT "$target"; fi
        log_event FILE_REQUESTED "$target" "mode=$mode"
        cat -- "$source" >&"$log_fd"
    fi
    staging="$(mktemp "$target.tmp.XXXXXX")"
    if install -m "$mode" "$source" "$staging" && mv -fT "$staging" "$target"; then
        return 0
    fi
    rm -f -- "$staging"
    return 1
}

validate_choices() {
    local v name
    for v in ALLOW_LOCAL_NETWORK ALLOW_PRINTING ALLOW_BLUETOOTH; do
        case "${!v}" in yes|no) ;; *) die "$v must be yes or no" ;; esac
    done
    [ "${#UNTRUSTED_INTERFACES[@]}" -gt 0 ] || die "UNTRUSTED_INTERFACES is empty"
    for name in "${UNTRUSTED_INTERFACES[@]}"; do
        [[ "$name" =~ ^[a-zA-Z0-9_.:-]+\*?$ ]] || die "invalid interface pattern: $name"
        [ "${#name}" -le 16 ] || die "interface pattern too long: $name"
        [ "$name" != lo ] || die "loopback cannot be an untrusted interface"
    done
}

interface_set() {
    local sep= name
    for name in "${UNTRUSTED_INTERFACES[@]}"; do
        printf '%s"%s"' "$sep" "$name"
        sep=', '
    done
}

render_rules() {
    local interfaces
    interfaces="$(interface_set)"
    cat <<RULES
#!/usr/sbin/nft -f
$MARKER
# Replace just our table in one transaction, including on the first run.
table inet $TABLE
delete table inet $TABLE
table inet $TABLE {
    comment "$OWNER"
    chain input {
        type filter hook input priority filter; policy drop;
        iifname "lo" accept
        ct state established,related accept
        ct state invalid drop
        icmp type { echo-reply, destination-unreachable, time-exceeded, parameter-problem } accept
        icmpv6 type {
            echo-reply, destination-unreachable, packet-too-big, time-exceeded,
            parameter-problem, nd-neighbor-solicit, nd-neighbor-advert,
            nd-router-advert, mld-listener-query, mld-listener-report,
            mld-listener-done, mld2-listener-report
        } accept
        meta nfproto ipv4 udp sport 67 udp dport 68 accept
        meta nfproto ipv6 udp sport 547 udp dport 546 accept
RULES
    if [ "$ALLOW_PRINTING" = yes ]; then
        echo "        iifname { $interfaces } udp sport 5353 udp dport 5353 accept"
    fi
    cat <<RULES
        counter comment "unsolicited input"
    }
    chain forward {
        type filter hook forward priority filter; policy accept;
        ct state established,related accept
        iifname { $interfaces } counter drop
    }
    chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
RULES
    if [ "$ALLOW_LOCAL_NETWORK" = no ]; then
        echo "        oifname { $interfaces } jump local_network"
    fi
    cat <<'RULES'
    }
    chain local_network {
        # Port exceptions do not authenticate DNS or DHCP servers.
        udp dport 53 accept
        tcp dport 53 accept
        meta nfproto ipv4 udp sport 68 udp dport 67 accept
        meta nfproto ipv6 udp sport 546 udp dport 547 accept
        meta l4proto { icmp, ipv6-icmp } accept
        ip protocol igmp accept
RULES
    if [ "$ALLOW_PRINTING" = yes ]; then
        cat <<'RULES'
        # Explicit exceptions for discovery and common printer protocols;
        # these ports do not prove the destination is a trusted printer.
        ip daddr 224.0.0.251 udp dport 5353 accept
        ip6 daddr ff02::fb udp dport 5353 accept
        tcp dport { 515, 631, 9100 } accept
RULES
    fi
    cat <<'RULES'
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
                   169.254.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 255.255.255.255 } counter drop
        ip6 daddr { fc00::/7, fe80::/10, ff00::/8 } counter drop
    }
}
RULES
}

render_unit() {
    cat <<UNIT
$MARKER
[Unit]
Description=Untrusted network host firewall
Wants=network-pre.target
Before=network-pre.target shutdown.target
After=nftables.service
PartOf=nftables.service
ReloadPropagatedFrom=nftables.service
Conflicts=shutdown.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $RULES_FILE
ExecReload=/usr/sbin/nft -f $RULES_FILE
ExecStop=/usr/sbin/nft destroy table inet $TABLE
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=sysinit.target
UNIT
}

# Permissions/netlink errors must never be mistaken for "table absent".
inspect_table() {
    nft -j list ruleset > "$work/live.json" || return
    python3 - "$work/live.json" "$TABLE" "$OWNER" "$1" <<'PY'
import json, sys
path, name, owner, mode = sys.argv[1:]
items = json.load(open(path))["nftables"]
table = next((x["table"] for x in items if "table" in x
              and x["table"].get("family") == "inet"
              and x["table"].get("name") == name), None)
if mode == "ownership":
    print("absent" if table is None else
          "owned" if table.get("comment") == owner else "foreign")
elif mode == "absent":
    if table is not None:
        sys.exit("firewall table is still loaded")
elif mode == "verify":
    if table is None or table.get("comment") != owner:
        sys.exit("managed firewall table was not loaded")
    chains = {x["chain"]["name"]: x["chain"] for x in items if "chain" in x
              and x["chain"].get("family") == "inet"
              and x["chain"].get("table") == name}
    for name, policy in (("input", "drop"), ("output", "accept"), ("forward", "accept")):
        chain = chains.get(name, {})
        if (chain.get("hook"), chain.get("policy"), chain.get("type")) != (name, policy, "filter"):
            sys.exit(f"unexpected {name} chain configuration")
PY
}

archive_legacy() {
    local archive="$STATE_DIR/legacy-backup" staging file
    # Match the four configurations generated by v1, ignoring comments/spacing.
    # A user-edited main ruleset needs a deliberate merge, not automatic removal.
    python3 - "$LEGACY_CONF" <<'PY'
import hashlib, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
tokens = re.sub(r"\s+", "", "\n".join(x.split("#", 1)[0] for x in text.splitlines()))
known = {
    "a0c73b91c6aea6e0e9cc875ad41a350db1fd951648a45d3dea53aa712f8628e9",
    "30ee31998eed3c4f7dc4514659bcc951ee9e065015a80a440bf19ecaa43394f0",
    "9af6c4b85202df8abd868fb5c6a9179fafd74ee35910bb9ee656c6b7f23e0c71",
    "89d1afd62d2d9c716467e6c4907d391c211dcf92980324cbc0711407bbe22a76",
}
if hashlib.sha256(tokens.encode()).hexdigest() not in known:
    sys.exit("legacy rules were edited; preserve the current firewall and merge its changes manually")
PY
    [ -f "$LEGACY_CONF.bak" ] || die "legacy configuration has no .bak; retain current rules and recover the original file first"
    [ ! -L "$LEGACY_CONF.bak" ] || die "legacy backup is a symlink"
    [ -f "$STATE_DIR/sysctl" ] && [ -f "$STATE_DIR/units" ] ||
        die "legacy recovery records are missing; retain current rules for manual recovery"
    if [ ! -d "$archive" ]; then
        staging="$(mktemp -d "$STATE_DIR/.legacy-backup.XXXXXX")"
        cp -a "$LEGACY_CONF" "$staging/nftables.conf.v1"
        cp -a "$LEGACY_CONF.bak" "$staging/nftables.conf.before-v1"
        cp -a "$STATE_DIR/sysctl" "$STATE_DIR/units" "$staging/"
        for file in "$SYSCTL_CONF" "$MODULE_CONF"; do
            if [ -f "$file" ]; then cp -a "$file" "$staging/"; fi
        done
        mv -T "$staging" "$archive"
    fi
    echo "retained    original recovery records in $STATE_DIR and $archive"
}

enable_firewall() {
    local legacy=no ownership
    validate_choices
    owned_path "$RULES_FILE"
    owned_path "$UNIT_FILE"
    if legacy_file "$LEGACY_CONF"; then
        owned_path "$LEGACY_CONF"
        legacy=yes
    fi
    ownership="$(inspect_table ownership)"
    [ "$ownership" != foreign ] || [ "$legacy" = yes ] ||
        die "table inet $TABLE exists but is not owned by this installation"
    render_rules > "$work/rules.nft"
    nft -c -f "$work/rules.nft"
    render_unit > "$work/$UNIT"
    systemd-analyze verify "$work/$UNIT"
    if [ "$legacy" = yes ]; then archive_legacy; fi
    atomic_install "$work/rules.nft" "$RULES_FILE"
    atomic_install "$work/$UNIT" "$UNIT_FILE"
    systemctl daemon-reload
    systemctl enable "$UNIT"
    # Load even if the service is already active; nft commits atomically.
    nft -f "$RULES_FILE"
    systemctl start "$UNIT"
    systemctl is-enabled --quiet "$UNIT"
    systemctl is-active --quiet "$UNIT"
    inspect_table verify
    if [ "$legacy" = yes ]; then
        # Restore the FILE only: never execute its possible "flush ruleset",
        # reload/stop nftables.service, consume .bak, or guess its prior state.
        atomic_install "$STATE_DIR/legacy-backup/nftables.conf.before-v1" "$LEGACY_CONF" \
            "$(stat -c '%a' "$STATE_DIR/legacy-backup/nftables.conf.before-v1")"
        echo "migrated    main nftables configuration restored without reloading it"
    fi
    echo "on          host inbound filtering loaded; dedicated boot service enabled"
    printf 'interfaces  %s\n' "${UNTRUSTED_INTERFACES[*]}"
    echo "hardening   unchanged; use --harden to apply kernel and service preferences"
}

disable_firewall() {
    local ownership
    if legacy_file "$LEGACY_CONF"; then
        die "old installation detected: run --enable once to migrate safely before using --disable"
    fi
    owned_path "$RULES_FILE"
    owned_path "$UNIT_FILE"
    ownership="$(inspect_table ownership)"
    [ "$ownership" != foreign ] || die "refusing to delete a table without our ownership marker"
    if [ -f "$UNIT_FILE" ]; then systemctl disable --now "$UNIT"; fi
    if [ "$ownership" = owned ]; then nft destroy table inet "$TABLE"; fi
    inspect_table absent
    echo "off         this firewall only; kernel settings, services, and backups retained"
}

set_services() {
    local want="$1" unit load active enabled
    shift
    local present=()
    for unit in "$@"; do
        load="$(systemctl show "$unit" -p LoadState --value)"
        case "$load" in
            not-found) printf 'absent      %s\n' "$unit" ;;
            loaded) present+=( "$unit" ) ;;
            *) die "cannot inspect $unit: LoadState=$load" ;;
        esac
    done
    [ "${#present[@]}" -gt 0 ] || return 0
    systemctl "$want" --now "${present[@]}"
    for unit in "${present[@]}"; do
        active="$(systemctl show "$unit" -p ActiveState --value)"
        enabled="$(systemctl show "$unit" -p UnitFileState --value)"
        if [ "$want" = disable ]; then
            [ "$active" = inactive ] || die "$unit is still $active"
            case "$enabled" in enabled*) die "$unit is still $enabled" ;; esac
        else
            [ "$active" = active ] || die "$unit did not start: $active"
        fi
        printf '%-11s %s (boot: %s, now: %s)\n' "$want" "$unit" "$enabled" "$active"
    done
}

harden() {
    local file module
    validate_choices
    owned_path "$SYSCTL_CONF"
    owned_path "$MODULE_CONF"
    if legacy_file "$LEGACY_CONF"; then
        die "run --enable first to archive and migrate the old installation"
    fi
    {
        echo "$MARKER"
        cat <<'SETTINGS'
# Persistent settings for current and subsequently created interfaces.
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.*.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.*.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.*.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = -1
# Loose reverse-path filtering accommodates common asymmetric/VPN routing.
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.log_martians = 1
SETTINGS
    } > "$work/sysctl.conf"
    {
        echo "$MARKER"
        echo '# Prevent ordinary modprobe loading; does not unload existing modules.'
        for module in dccp sctp rds tipc; do
            printf 'blacklist %s\ninstall %s /bin/false\n' "$module" "$module"
        done
    } > "$work/modules.conf"
    atomic_install "$work/sysctl.conf" "$SYSCTL_CONF"
    sysctl -p "$SYSCTL_CONF"
    for file in /proc/sys/net/ipv4/conf/*/accept_redirects /proc/sys/net/ipv6/conf/*/accept_redirects \
                /proc/sys/net/ipv4/conf/*/send_redirects; do
        [ -f "$file" ] || continue
        [ "$(cat "$file")" = 0 ] || die "setting did not take effect: $file"
    done
    atomic_install "$work/modules.conf" "$MODULE_CONF"
    for module in dccp sctp rds tipc; do
        if [ -d "/sys/module/$module" ]; then
            printf 'present     %s remains in the running kernel; it was not unloaded\n' "$module"
        fi
    done
    set_services enable NetworkManager.service
    if [ "$ALLOW_PRINTING" = yes ]; then
        set_services enable "${PRINTING_UNITS[@]}"
    else
        set_services disable "${PRINTING_UNITS[@]}"
    fi
    set_services disable ModemManager.service
    if [ "$ALLOW_BLUETOOTH" = yes ]; then
        set_services enable bluetooth.service
        # Apply now; Bluetooth apps or restarts can change these settings again.
        bluetoothctl --timeout 10 pairable off
        bluetoothctl --timeout 10 discoverable off
    else
        set_services disable bluetooth.service
    fi
    # Installing unattended-upgrades alone does not enable scheduled updates.
    cat > "$work/auto-upgrades" <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
    atomic_install "$work/auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
    echo "automatic security updates: on"
    echo "applied     persistent hardening; --disable will not undo these settings"
    echo "services    stopped/disabled services can still be activated explicitly"
}

show_status() {
    local unit file state result=0
    for unit in "$UNIT" nftables.service "${PRINTING_UNITS[@]}" "${OTHER_UNITS[@]}"; do
        if state="$(systemctl show "$unit" -p LoadState -p ActiveState -p UnitFileState)"; then
            printf '%s\n%s\n\n' "$unit" "$state"
        else
            printf '%s: inspection failed\n' "$unit" >&2
            result=1
        fi
    done
    if legacy_file "$LEGACY_CONF"; then echo 'legacy      run --enable to migrate this installation'; fi
    if [ "$(id -u)" -eq 0 ]; then
        if state="$(inspect_table ownership)"; then
            case "$state" in
                absent) echo "rules       no table inet $TABLE loaded" ;;
                *) nft list table inet "$TABLE" || result=1 ;;
            esac
        else
            echo "rules       inspection failed; current protection is unknown" >&2
            result=1
        fi
    else
        echo "rules       run this command with sudo to inspect loaded filtering"
    fi
    for file in /proc/sys/net/ipv4/conf/*/{accept_redirects,send_redirects,accept_source_route,rp_filter,log_martians} \
                /proc/sys/net/ipv6/conf/*/{accept_redirects,accept_source_route}; do
        [ -e "$file" ] || continue
        if state="$(cat "$file")"; then
            printf '%s=%s\n' "$file" "$state"
        else
            printf '%s: inspection failed\n' "$file" >&2
            result=1
        fi
    done
    return "$result"
}

run_action() {
    local action="$1" command
    for command in nft python3 systemctl mktemp flock install sysctl systemd-analyze; do
        command -v "$command" >/dev/null || die "missing command: $command"
    done
    work="$(mktemp -d)"
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "another firewall operation is running"
    log_state_ready=yes
    record_state before
    case "$action" in
        --enable) enable_firewall ;;
        --disable) disable_firewall ;;
        --harden) harden ;;
    esac
}

main() {
    local action="${1:-}" command
    if [ "$#" -ne 1 ]; then usage >&2; return 1; fi
    case "$action" in
        -h|--help) usage; return 0 ;;
        --enable|--disable|--status|--harden) ;;
        *) printf 'error: unknown action: %s\n\n' "$action" >&2; usage >&2; return 1 ;;
    esac
    if [ "$action" = --status ]; then
        for command in nft python3 systemctl mktemp; do
            command -v "$command" >/dev/null || die "missing command: $command (install nftables, python3, systemd)"
        done
        work="$(mktemp -d)"
        trap 'rm -rf -- "$work"' EXIT
        show_status
        return
    fi
    [ "$(id -u)" -eq 0 ] || die "run with sudo: sudo $0 $action"
    for command in tee stat sha256sum; do
        command -v "$command" >/dev/null || die "missing command: $command"
    done
    umask 077
    run_logged "$action"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
