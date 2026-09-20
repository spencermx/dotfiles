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
#
# This blocks unsolicited connections to the host, with control exceptions.
# Existing connections remain allowed. It does not authenticate routers/DHCP/DNS,
# encrypt traffic, prevent malicious downloads, or hide you. Local isolation is
# partial: DNS/control traffic and public destinations remain reachable, including
# neighbors with public IPv4/IPv6 addresses.

ALLOW_LOCAL_NETWORK=no
ALLOW_PRINTING=no
ALLOW_BLUETOOTH=no

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
PRINTING_UNITS=( cups.service cups.socket cups.path cups-browsed.service avahi-daemon.service avahi-daemon.socket )
OTHER_UNITS=( ModemManager.service bluetooth.service )
work=

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<HELP
Usage: $0 OPTION

  --enable   Load/update firewall rules and enable them at boot.
  --disable  Remove only this firewall's rules.
  --status   Show service states and kernel settings; sudo also shows live rules.
  --harden   Apply persistent kernel/module restrictions and service preferences.
  -h, --help Show this help without changing anything.

Use sudo for --enable, --disable, and --harden.
--disable leaves hardening and service settings in place.

Preferences at the top of this script:
  ALLOW_LOCAL_NETWORK=$ALLOW_LOCAL_NETWORK
  ALLOW_PRINTING=$ALLOW_PRINTING
  ALLOW_BLUETOOTH=$ALLOW_BLUETOOTH

Run --enable after changing network or printing rules.
Run --harden to apply printing, discovery, modem, and Bluetooth service settings.
See firewall.md for details about protection, interface scope, and migration.
HELP
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
    if [ "$ALLOW_PRINTING" = yes ]; then
        set_services enable "${PRINTING_UNITS[@]}"
    else
        set_services disable "${PRINTING_UNITS[@]}"
    fi
    set_services disable ModemManager.service
    if [ "$ALLOW_BLUETOOTH" = yes ]; then
        set_services enable bluetooth.service
    else
        set_services disable bluetooth.service
    fi
    echo "applied     persistent hardening; --disable will not undo these settings"
    echo "services    stopped/disabled services can still be activated explicitly"
}

show_status() {
    local unit file state result=0
    for unit in "$UNIT" "${PRINTING_UNITS[@]}" "${OTHER_UNITS[@]}"; do
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
    for file in /proc/sys/net/ipv4/conf/*/accept_redirects /proc/sys/net/ipv6/conf/*/accept_redirects; do
        [ -r "$file" ] || continue
        printf '%s=%s\n' "$file" "$(cat "$file")"
    done
    return "$result"
}

main() {
    local action="${1:-}" command
    if [ "$#" -ne 1 ]; then usage >&2; return 1; fi
    case "$action" in
        -h|--help) usage; return 0 ;;
        --enable|--disable|--status|--harden) ;;
        *) printf 'error: unknown action: %s\n\n' "$action" >&2; usage >&2; return 1 ;;
    esac
    for command in nft python3 systemctl mktemp; do
        command -v "$command" >/dev/null || die "missing command: $command (install nftables, python3, systemd)"
    done
    work="$(mktemp -d)"
    trap 'rm -rf -- "$work"' EXIT
    if [ "$action" = --status ]; then show_status; return; fi
    [ "$(id -u)" -eq 0 ] || die "run with sudo: sudo $0 $action"
    for command in flock install sysctl systemd-analyze; do
        command -v "$command" >/dev/null || die "missing command: $command"
    done
    umask 077
    exec 9>"$LOCK_FILE"
    flock -n 9 || die "another firewall operation is running"
    case "$action" in
        --enable) enable_firewall ;;
        --disable) disable_firewall ;;
        --harden) harden ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
