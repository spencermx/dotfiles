#!/usr/bin/env python3
"""Real IPv4/IPv6 packet checks; the launcher creates disposable namespaces:

python3 debian/tests/check_firewall_network.py

The child verifies both namespaces differ from its launcher's. No sudo is needed.
"""
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1] / "firewall.sh"
NFT = "/usr/sbin/nft"
SERVER = r"""
import selectors, socket, struct
selector = selectors.DefaultSelector()
for family, address in ((socket.AF_INET, "0.0.0.0"), (socket.AF_INET6, "::")):
    for port in (53, 631, 8443):
        sock = socket.socket(family)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if family == socket.AF_INET6:
            sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        sock.bind((address, port))
        sock.listen()
        selector.register(sock, selectors.EVENT_READ, "tcp")
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
udp.bind(("", 5353))
# Only the external peer needs discovery membership.
try:
    udp.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                   socket.inet_aton("224.0.0.251") + socket.inet_aton("10.12.0.2"))
except OSError:
    pass
selector.register(udp, selectors.EVENT_READ, "udp")
print("ready", flush=True)
while True:
    for key, _ in selector.select():
        if key.data == "tcp":
            client, _ = key.fileobj.accept()
            client.sendall(b"ok")
            client.close()
        else:
            data, peer = key.fileobj.recvfrom(1024)
            key.fileobj.sendto(b"ok", peer)
"""
CLIENT = r"""
import socket, sys
try:
    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=0.5) as sock:
        assert sock.recv(2) == b"ok"
except (OSError, AssertionError):
    sys.exit(1)
"""

def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs)

def main():
    if len(sys.argv) == 1:
        previous = [os.readlink(f"/proc/self/ns/{kind}") for kind in ("net", "user")]
        return subprocess.call(["unshare", "--user", "--map-root-user", "--net",
                                sys.executable, str(Path(__file__).resolve()), "--isolated", *previous])
    if len(sys.argv) != 4 or sys.argv[1] != "--isolated":
        raise SystemExit("Run this test without arguments; it creates its own namespaces.")
    for kind, previous in zip(("net", "user"), sys.argv[2:]):
        if os.readlink(f"/proc/self/ns/{kind}") == previous:
            raise SystemExit("Refusing to run outside disposable user AND network namespaces.")
    processes = []
    checks = 0

    def check(label, condition):
        nonlocal checks
        if not condition:
            raise AssertionError(label)
        checks += 1
        print("PASS", label, flush=True)

    def peer(host_link, peer_link, host4, peer4, host6, peer6):
        proc = subprocess.Popen(["unshare", "--net", "sleep", "120"])
        processes.append(proc)
        deadline = time.monotonic() + 5
        parent_ns = os.readlink("/proc/self/ns/net")
        while os.readlink(f"/proc/{proc.pid}/ns/net") == parent_ns:
            if time.monotonic() > deadline:
                raise RuntimeError("peer namespace did not start")
            time.sleep(0.01)
        run("ip", "link", "add", host_link, "type", "veth", "peer", "name", peer_link)
        run("ip", "link", "set", peer_link, "netns", str(proc.pid))
        run("ip", "link", "set", host_link, "up")
        run("ip", "addr", "add", host4, "dev", host_link)
        run("ip", "-6", "addr", "add", host6, "dev", host_link, "nodad")
        prefix = ["nsenter", "-t", str(proc.pid), "-n"]
        run(*prefix, "ip", "link", "set", "lo", "up")
        run(*prefix, "ip", "link", "set", peer_link, "up")
        run(*prefix, "ip", "addr", "add", peer4, "dev", peer_link)
        run(*prefix, "ip", "-6", "addr", "add", peer6, "dev", peer_link, "nodad")
        return prefix

    def server(prefix):
        proc = subprocess.Popen(prefix + ["python3", "-u", "-c", SERVER],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(proc)
        ready, _, _ = select.select([proc.stdout], [], [], 5)
        if not ready or proc.stdout.readline().strip() != "ready":
            raise RuntimeError("test listener failed to start")

    def connect(address, port=8443, prefix=None):
        result = subprocess.run((prefix or []) + ["python3", "-c", CLIENT, address, str(port)],
                                capture_output=True, text=True, timeout=3)
        return result.returncode == 0

    def discovery():
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            # The peer returns a unicast reply to a multicast query. This also
            # exercises the explicit inbound discovery exception.
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("10.12.0.1", 5353))
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton("10.12.0.1"))
            sock.settimeout(0.5)
            try:
                sock.sendto(b"query", ("224.0.0.251", 5353))
                return sock.recv(2) == b"ok"
            except OSError:
                return False

    try:
        run("ip", "link", "set", "lo", "up")
        outside = peer("wltest0", "peer0", "10.12.0.1/24", "10.12.0.2/24",
                       "fd12::1/64", "fd12::2/64")
        run("ip", "addr", "add", "192.0.2.1/24", "dev", "wltest0")
        run(*outside, "ip", "addr", "add", "192.0.2.2/24", "dev", "peer0")
        run("ip", "-6", "addr", "add", "2001:db8:12::1/64", "dev", "wltest0", "nodad")
        run(*outside, "ip", "-6", "addr", "add", "2001:db8:12::2/64", "dev", "peer0", "nodad")
        container = peer("veth-test0", "container0", "172.18.0.1/24", "172.18.0.2/24",
                         "fd18::1/64", "fd18::2/64")
        run(*container, "ip", "route", "add", "default", "via", "172.18.0.1")
        run(*container, "ip", "-6", "route", "add", "default", "via", "fd18::1")
        run(*outside, "ip", "route", "add", "172.18.0.0/24", "via", "10.12.0.1")
        run(*outside, "ip", "-6", "route", "add", "fd18::/64", "via", "fd12::1")
        # These are per-network-namespace sysctls, changed only in this disposable namespace.
        run("/usr/sbin/sysctl", "-qw", "net.ipv4.ip_forward=1", "net.ipv6.conf.all.forwarding=1")
        server(outside)
        server(container)
        # No parent UDP listener: the discovery client binds port 5353 itself.
        parent_server = SERVER.replace('udp.bind(("", 5353))', 'udp.bind(("", 15353))')
        proc = subprocess.Popen(["python3", "-u", "-c", parent_server],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(proc)
        ready, _, _ = select.select([proc.stdout], [], [], 5)
        if not ready or proc.stdout.readline().strip() != "ready":
            raise RuntimeError("host listener failed to start")
        run(NFT, "add", "table", "inet", "unrelated_test")
        original = json.loads(run(NFT, "-j", "list", "table", "inet", "unrelated_test").stdout)
        with tempfile.TemporaryDirectory(prefix="firewall-packets-") as temp:
            rules = Path(temp) / "rules.nft"

            def load(local="no", printing="no"):
                result = run("bash", "-c",
                             'source "$1"; ALLOW_LOCAL_NETWORK="$2"; ALLOW_PRINTING="$3"; validate_choices; render_rules',
                             "bash", str(SOURCE), local, printing)
                rules.write_text(result.stdout)
                run(NFT, "-c", "-f", str(rules))
                run(NFT, "-f", str(rules))

            load()
            check("IPv4 unsolicited input blocked", not connect("192.0.2.1", prefix=outside))
            check("IPv6 unsolicited input blocked", not connect("2001:db8:12::1", prefix=outside))
            check("IPv4 public outbound and replies work", connect("192.0.2.2"))
            check("IPv6 public outbound and replies work", connect("2001:db8:12::2"))
            check("IPv4 private LAN blocked", not connect("10.12.0.2"))
            check("IPv6 private LAN blocked", not connect("fd12::2"))
            check("IPv4 loopback works", connect("127.0.0.1"))
            check("IPv6 loopback works", connect("::1"))
            check("local DNS TCP exception works", connect("10.12.0.2", 53))
            check("printer blocked by default", not connect("10.12.0.2", 631))
            check("printer discovery blocked by default", not discovery())
            check("host can reach its container", connect("172.18.0.2"))
            check("container IPv4 outbound and replies work", connect("192.0.2.2", prefix=container))
            check("container IPv6 outbound and replies work", connect("2001:db8:12::2", prefix=container))
            check("IPv4 unsolicited forwarding from LAN blocked", not connect("172.18.0.2", prefix=outside))
            check("IPv6 unsolicited forwarding from LAN blocked", not connect("fd18::2", prefix=outside))
            load(printing="yes")
            check("IPv4 printing exception works", connect("10.12.0.2", 631))
            check("IPv6 printing exception works", connect("fd12::2", 631))
            check("printer discovery exception works", discovery())
            check("printing leaves other private ports blocked", not connect("10.12.0.2"))
            load(local="yes")
            check("local-network opt-in permits IPv4", connect("10.12.0.2"))
            check("local-network opt-in permits IPv6", connect("fd12::2"))
            check("local-network opt-in retains inbound protection", not connect("192.0.2.1", prefix=outside))
            load()
            run("ip", "link", "set", "wltest0", "name", "tun-test0")
            check("private destinations on tunnel-named interface work", connect("10.12.0.2"))
            run(NFT, "destroy", "table", "inet", "untrusted_network")
            run(NFT, "destroy", "table", "inet", "untrusted_network")
            check("disable removes inbound filtering", connect("192.0.2.1", prefix=outside))
            current = json.loads(run(NFT, "-j", "list", "table", "inet", "unrelated_test").stdout)
            # The metainfo version header is stable during this process.
            check("unrelated firewall table preserved", original == current)
        print(f"{checks} packet checks passed")
    finally:
        for proc in reversed(processes):
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

if __name__ == "__main__":
    sys.exit(main())
