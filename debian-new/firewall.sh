#!/usr/bin/env bash
# Lock this machine down on a network you do not trust.
#
#   sudo ./firewall.sh --enable     lock it down
#   sudo ./firewall.sh --disable    undo it
#        ./firewall.sh --status     show what is on right now (no root needed)
#
# This is NOT part of run-all.sh. It is a switch you throw yourself.
#
# WHAT IT DOES
#
#   1. Firewall, inbound: deny by default. Replies to conversations this
#      machine starts still come back, so browsing and apt work normally.
#      Nothing on the network can open a connection TO this machine.
#
#   2. Firewall, outbound: blocks most traffic aimed at the local network,
#      so this machine does not go looking for the devices around it.
#      Internet traffic is untouched: it is addressed to public IPs and only
#      passes through the router.
#
#   3. Turns off services that exist to talk to the local network: printing
#      (CUPS and its discovery), mDNS, and the cellular-modem manager.
#
#   4. Kernel settings: ignore anything on the LAN claiming to reroute your
#      traffic, and refuse to load four network protocols nothing here uses.
#
# WHAT IT DOES NOT DO. Being accurate about this matters more than the
# feature list:
#
#   - It does not make the machine invisible. It still answers ARP and IPv6
#     neighbour discovery, because it cannot use the network otherwise.
#     Anything on the wifi can still tell it is there.
#   - LAN blocking is partial, not a wall. DNS, DHCP and ICMP are allowed
#     through by necessity, and IPv6 neighbours with ordinary global
#     addresses are not blocked at all, because their addresses are
#     indistinguishable from the rest of the internet.
#   - It does nothing about a hostile router or a neighbour impersonating
#     one. ARP and router advertisements are below this layer.
#   - It does nothing about what you choose to run. A bad download or a
#     browser exploit leaves over port 443, which must stay open.
#
# --disable restores the sysctl values and service states recorded when you
# ran --enable, so it puts back what was actually there rather than guessing.
#
#---------------------------------------------------------------------------
# The three choices. Flip one and re-run --enable; changes apply immediately
# and turning one back to "yes" re-enables what it turned off.
#---------------------------------------------------------------------------

# Talk to other devices on the wifi. Turn this on temporarily when you need
# the router's admin page, a NAS, or a hotel/airport sign-in page.
ALLOW_LOCAL_NETWORK=no

# Printing. Covers CUPS itself and finding printers over the network.
ALLOW_PRINTING=no

# Bluetooth. Nothing is paired today. A mouse, keyboard or headphones needs
# this. Note that these firewall rules do not govern bluetooth either way.
ALLOW_BLUETOOTH=no

set -euo pipefail

TABLE="untrusted_network"          # our own nftables table; nothing else is touched
NFT_CONF="/etc/nftables.conf"
SYSCTL_CONF="/etc/sysctl.d/99-untrusted-network.conf"
MODULE_CONF="/etc/modprobe.d/99-untrusted-network.conf"
STATE_DIR="/var/lib/untrusted-network-firewall"

PRINTING_UNITS="cups.service cups.socket cups.path cups-browsed.service avahi-daemon.service avahi-daemon.socket"
MODEM_UNITS="ModemManager.service"
BLUETOOTH_UNITS="bluetooth.service"
ALL_UNITS="$PRINTING_UNITS $MODEM_UNITS $BLUETOOTH_UNITS"

# Sysctls this script changes. Saved before the first change so --disable can
# put the live values back; deleting a file in /etc/sysctl.d does NOT do that.
MANAGED_SYSCTLS="
net.ipv4.conf.all.accept_redirects
net.ipv4.conf.default.accept_redirects
net.ipv6.conf.all.accept_redirects
net.ipv6.conf.default.accept_redirects
net.ipv4.conf.all.send_redirects
net.ipv4.conf.default.send_redirects
net.ipv4.conf.all.accept_source_route
net.ipv6.conf.all.accept_source_route
net.ipv4.conf.all.rp_filter
net.ipv4.conf.default.rp_filter
net.ipv4.conf.all.log_martians
"

#---------------------------------------------------------------------------
# status: safe to run as anyone
#---------------------------------------------------------------------------
unit_state() {
    local s
    s="$(systemctl is-enabled "$1" 2>/dev/null)" || true
    [ -n "$s" ] && printf '%s' "$s" || printf 'not-found'
}

show_status() {
    echo "firewall"
    printf '  nftables at boot:    %s\n' "$(unit_state nftables)"
    if [ "$(id -u)" -eq 0 ]; then
        if nft list table inet "$TABLE" >/dev/null 2>&1; then
            printf '  rules loaded now:    yes, table inet %s\n' "$TABLE"
            printf '  inbound policy:      %s\n' "$(nft list chain inet "$TABLE" input 2>/dev/null | grep -oE 'policy [a-z]+' | head -1 || echo unknown)"
            printf '  local network:       %s\n' "$(nft list chain inet "$TABLE" output 2>/dev/null | grep -q 'daddr' && echo 'mostly blocked' || echo 'reachable')"
        else
            echo "  rules loaded now:    no"
        fi
    else
        echo "  (run with sudo to see the loaded ruleset)"
    fi

    echo "kernel settings"
    printf '  accept redirects:    ipv4=%s ipv6=%s   (0 is what you want)\n' \
        "$(cat /proc/sys/net/ipv4/conf/all/accept_redirects)" \
        "$(cat /proc/sys/net/ipv6/conf/all/accept_redirects)"
    printf '  reverse-path filter: %s              (2 = loose, safe with VPNs)\n' "$(cat /proc/sys/net/ipv4/conf/all/rp_filter)"
    printf '  settings file:       %s\n' "$([ -e "$SYSCTL_CONF" ] && echo present || echo absent)"
    printf '  module overrides:    %s\n' "$([ -e "$MODULE_CONF" ] && echo 'dccp sctp rds tipc set to not load' || echo none)"

    echo "services that talk to the local network"
    for u in $ALL_UNITS; do
        printf '  %-24s %s\n' "$u" "$(unit_state "$u")"
    done

    echo "sockets open on this machine"
    ss -tulnH 2>/dev/null \
        | awk '$5 !~ /^(127\.|\[::1\])/ {printf "  %-4s %s\n", $1, $5}' \
        | sort -u || true
    echo "  (listed = a program is listening; with the firewall on, inbound"
    echo "   connections to these are dropped before they arrive)"
}

#---------------------------------------------------------------------------
# argument handling
#---------------------------------------------------------------------------
case "${1:-}" in
    --status) show_status; exit 0 ;;
    --enable|--disable) action="$1" ;;
    *)
        echo "usage: sudo $0 --enable | --disable"
        echo "       $0 --status"
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "run this with sudo: sudo $0 $action" >&2
    exit 1
fi

# A typo in one of the three switches must not silently skip protections.
for v in ALLOW_LOCAL_NETWORK ALLOW_PRINTING ALLOW_BLUETOOTH; do
    case "${!v}" in
        yes|no) ;;
        *) echo "$v must be exactly 'yes' or 'no', not '${!v}'" >&2; exit 1 ;;
    esac
done

# Report what actually happened instead of calling every failure "not present".
set_units() { # set_units <enable|disable> <units...>
    local want="$1"; shift
    for u in "$@"; do
        if ! systemctl cat "$u" >/dev/null 2>&1; then
            printf '  --   %-24s not on this machine\n' "$u"; continue
        fi
        if systemctl "$want" --now "$u" >/dev/null 2>&1; then
            printf '  %-4s %s\n' "$([ "$want" = disable ] && echo off || echo on)" "$u"
        else
            printf '  FAIL %-24s systemctl %s failed (masked? see: systemctl status %s)\n' "$u" "$want" "$u"
        fi
    done
}

#---------------------------------------------------------------------------
# --disable
#---------------------------------------------------------------------------
if [ "$action" = "--disable" ]; then
    nft delete table inet "$TABLE" 2>/dev/null \
        && echo "removed     firewall rules (table inet $TABLE)" \
        || echo "--          no $TABLE table was loaded"
    systemctl disable --now nftables >/dev/null 2>&1 || true
    echo "removed     nftables no longer starts at boot"

    if [ -e "$NFT_CONF.bak" ]; then
        mv "$NFT_CONF.bak" "$NFT_CONF"
        echo "restored    $NFT_CONF as it was before --enable"
    fi

    for f in "$SYSCTL_CONF" "$MODULE_CONF"; do
        if [ -e "$f" ]; then rm -f "$f"; echo "removed     $f"; fi
    done

    # Put the live kernel values back. Removing the file above does not.
    if [ -r "$STATE_DIR/sysctl" ]; then
        while read -r key value; do
            [ -n "${key:-}" ] || continue
            sysctl -qw "$key=$value" 2>/dev/null || true
        done < "$STATE_DIR/sysctl"
        for d in /proc/sys/net/ipv4/conf/*/accept_redirects /proc/sys/net/ipv6/conf/*/accept_redirects; do
            [ -w "$d" ] && echo 1 > "$d" 2>/dev/null || true
        done
        echo "restored    kernel settings recorded at --enable"
    else
        echo "--          no saved kernel settings; values stay until reboot"
    fi

    # Put each service back to the state it was in, not to a blanket "on".
    if [ -r "$STATE_DIR/units" ]; then
        while read -r u s; do
            [ -n "${u:-}" ] || continue
            case "$s" in
                enabled|enabled-runtime|static|indirect|alias) set_units enable "$u" ;;
                *) printf '  --   %-24s left %s, as it was before\n' "$u" "$s" ;;
            esac
        done < "$STATE_DIR/units"
    else
        echo "--          no saved service states; re-enabling Debian's defaults"
        set_units enable $ALL_UNITS
    fi

    rm -rf "$STATE_DIR"
    echo
    show_status
    exit 0
fi

#---------------------------------------------------------------------------
# --enable, step 0: record what is here now, so --disable can put it back
#---------------------------------------------------------------------------
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
if [ ! -e "$STATE_DIR/sysctl" ]; then
    for k in $MANAGED_SYSCTLS; do
        v="$(sysctl -n "$k" 2>/dev/null)" || continue
        # A key with no readable value must not be written: --disable would
        # then try to set it to nothing.
        [ -n "$v" ] || continue
        printf '%s %s\n' "$k" "$v"
    done > "$STATE_DIR/sysctl"
    echo "saved       current kernel settings for --disable"
fi
if [ ! -e "$STATE_DIR/units" ]; then
    for u in $ALL_UNITS; do printf '%s %s\n' "$u" "$(unit_state "$u")"; done > "$STATE_DIR/units"
    echo "saved       current service states for --disable"
fi

#---------------------------------------------------------------------------
# --enable, step 1: the firewall
#---------------------------------------------------------------------------
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Our own table, created and replaced atomically. Deliberately NOT "flush
# ruleset": that would delete every other table too, including ones docker or
# a VPN may add later.
cat > "$tmp" <<RULES
#!/usr/sbin/nft -f
# Written by debian-new/firewall.sh --enable

table inet $TABLE
delete table inet $TABLE

table inet $TABLE {
RULES

cat >> "$tmp" <<'RULES'
    chain input {
        type filter hook input priority filter; policy drop;

        # Replies to conversations this machine started. This one rule is
        # what keeps browsing, apt and everything else working.
        ct state established,related accept
        ct state invalid drop
        iif lo accept

        # ICMP. Blocking all of it breaks path-MTU discovery, which shows up
        # as websites that hang forever. Echo REQUESTS are not accepted, so
        # the machine does not answer pings.
        meta l4proto icmp icmp type {
            echo-reply, destination-unreachable, time-exceeded, parameter-problem
        } accept

        # ICMPv6 is not optional; IPv6 stops working without neighbour
        # discovery. "meta l4proto ipv6-icmp" rather than "ip6 nexthdr": MLD
        # arrives behind a hop-by-hop extension header, which nexthdr misses.
        meta l4proto ipv6-icmp icmpv6 type {
            echo-reply, destination-unreachable, packet-too-big, time-exceeded,
            parameter-problem, nd-neighbor-solicit, nd-neighbor-advert,
            nd-router-advert, mld-listener-query, mld2-listener-report
        } accept

        # Keep being able to get an IP address.
        udp sport 67 udp dport 68 accept
        udp sport 547 udp dport 546 accept
RULES

if [ "$ALLOW_PRINTING" = "yes" ]; then
    cat >> "$tmp" <<'RULES'

        # ALLOW_PRINTING=yes: let network printers be discovered.
        udp dport 5353 accept
RULES
fi

cat >> "$tmp" <<'RULES'
    }

    # This machine is not a router; never pass other people's traffic.
    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
        oif lo accept
RULES

if [ "$ALLOW_LOCAL_NETWORK" = "no" ]; then
    cat >> "$tmp" <<'RULES'

        # Getting an address, looking up names, and the IPv6/IPv4 control
        # protocols all have to reach the local network. Note these are port
        # and protocol matches only: they are exceptions, not verification
        # that the traffic really is DNS.
        udp dport { 53, 67, 547 } accept
        tcp dport 53 accept
        meta l4proto icmp accept
        meta l4proto ipv6-icmp accept
        ip protocol igmp accept

        # Everything else aimed at the local network. Internet traffic is
        # unaffected: it is addressed to public IPs and only passes through
        # the router. IPv6 neighbours holding ordinary global addresses are
        # NOT blocked here; their addresses look like the rest of the
        # internet and cannot be told apart by a static rule.
        ip daddr {
            10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
            169.254.0.0/16, 100.64.0.0/10, 224.0.0.0/4, 255.255.255.255
        } drop
        ip6 daddr { fc00::/7, fe80::/10, ff00::/8 } drop
RULES
fi

cat >> "$tmp" <<'RULES'
    }
}
RULES

# Never install a ruleset the kernel would reject.
if ! nft -c -f "$tmp"; then
    echo "the ruleset was rejected; nothing was changed" >&2
    exit 1
fi

if [ -e "$NFT_CONF" ] && [ ! -e "$NFT_CONF.bak" ]; then
    cp "$NFT_CONF" "$NFT_CONF.bak"
    echo "saved       $NFT_CONF.bak (the file that was there before)"
fi
install -m 644 "$tmp" "$NFT_CONF"

# Load it NOW. "systemctl enable --now" only starts a stopped service, so on
# every run after the first it would leave the old rules in place while
# reporting success. Load explicitly, then enable for the next boot.
nft -f "$NFT_CONF"
systemctl enable nftables >/dev/null 2>&1 || true
nft list table inet "$TABLE" >/dev/null 2>&1 \
    || { echo "rules did not load; nothing is protecting you" >&2; exit 1; }
echo "on          firewall: inbound denied by default (loaded and verified)"
if [ "$ALLOW_LOCAL_NETWORK" = "no" ]; then
    echo "on          firewall: most local-network traffic blocked outbound"
else
    echo "--          local network reachable (ALLOW_LOCAL_NETWORK=yes)"
fi

#---------------------------------------------------------------------------
# --enable, step 2: kernel settings
#---------------------------------------------------------------------------
cat > "$SYSCTL_CONF" <<'SETTINGS'
# Written by debian-new/firewall.sh --enable

# Ignore ICMP redirects. Without this a device on the LAN can tell this
# machine "route your traffic through me instead of the gateway".
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# This machine is not a router and should never issue redirects either.
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Refuse source-routed packets. For IPv6, 0 still permits routing header
# type 2; -1 is the value that refuses routing headers outright.
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = -1

# Loose reverse-path filtering: drop packets whose source address is not
# routable back out of any interface. Strict mode (1) breaks VPNs and
# policy routing, so it is deliberately not used.
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# Log packets with impossible source addresses. Diagnostics, not protection.
net.ipv4.conf.all.log_martians = 1
SETTINGS
chmod 644 "$SYSCTL_CONF"
sysctl --system >/dev/null

# "default" only covers interfaces created later, and per-interface values
# already set can survive. Apply to the interfaces that exist right now.
for d in /proc/sys/net/ipv4/conf/*/accept_redirects /proc/sys/net/ipv6/conf/*/accept_redirects; do
    [ -w "$d" ] && echo 0 > "$d" 2>/dev/null || true
done
echo "on          kernel settings: redirects ignored on every interface"

#---------------------------------------------------------------------------
# --enable, step 3: network protocols nothing here uses
#---------------------------------------------------------------------------
cat > "$MODULE_CONF" <<'MODULES'
# Written by debian-new/firewall.sh --enable
# Four networking protocols this machine has never used, each with a history
# of remote kernel vulnerabilities. This stops them being auto-loaded on
# demand. It does not unload an already-loaded module or affect anything
# built into the kernel.
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
MODULES
chmod 644 "$MODULE_CONF"
echo "on          dccp, sctp, rds, tipc set to not load (none is loaded now)"

#---------------------------------------------------------------------------
# --enable, step 4: services that exist to talk to the local network
#---------------------------------------------------------------------------
# Written as if/else, not "test && a || b": if the first branch ever returned
# non-zero the || would run the second branch as well.
if [ "$ALLOW_PRINTING" = "yes" ]; then
    set_units enable $PRINTING_UNITS
else
    set_units disable $PRINTING_UNITS
fi

set_units disable $MODEM_UNITS

if [ "$ALLOW_BLUETOOTH" = "yes" ]; then
    set_units enable $BLUETOOTH_UNITS
else
    set_units disable $BLUETOOTH_UNITS
fi

echo
show_status
echo
echo "undo all of this with: sudo $0 --disable"
