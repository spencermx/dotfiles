#!/usr/bin/env python3
"""Save the original host state before running firewall.sh --enable or --harden.

Run ./debian/firewall-snapshot.py --sudo from a regular host terminal. Sudo is
used only to read live nftables rules. Each invocation creates a private snapshot
under .firewall-baselines/ in this repository and preserves earlier captures.
No firewall rules, kernel settings, modules, or services are changed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import tarfile


REPO = Path(__file__).resolve().parent.parent
SNAPSHOTS = REPO / ".firewall-baselines"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sudo", action="store_true", help="use sudo only to read live nftables rules")
    args = parser.parse_args()
    if args.sudo and os.geteuid() != 0:
        subprocess.run(["sudo", "-v"], check=True)
    os.umask(0o077)
    started = datetime.now(timezone.utc).isoformat()
    SNAPSHOTS.mkdir(mode=0o700, exist_ok=True)
    destination = SNAPSHOTS / (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    )
    destination.mkdir(mode=0o700)
    commands = {}
    errors = []

    def save(name, value):
        (destination / name).write_text(json.dumps(value, indent=2) + "\n")

    def capture(name, argv):
        try:
            result = subprocess.run(argv, capture_output=True, text=True, timeout=30)
            record = dict(argv=argv, returncode=result.returncode,
                          stdout=result.stdout, stderr=result.stderr)
        except (OSError, subprocess.TimeoutExpired) as exc:
            record = dict(argv=argv, returncode=None, stdout="", stderr=str(exc))
        commands[name] = record
        (destination / (name + ".txt")).write_text(record["stdout"])
        if record["returncode"] != 0:
            errors.append({"command": name, "error": record["stderr"]})
        return record

    units = ["untrusted-network-firewall.service", "nftables.service",
             "cups.service", "cups.socket", "cups.path", "cups-browsed.service",
             "avahi-daemon.service", "avahi-daemon.socket", "ModemManager.service",
             "bluetooth.service", "ufw.service", "firewalld.service",
             "netfilter-persistent.service", "NetworkManager.service"]
    properties = ["Id", "Names", "LoadState", "ActiveState", "SubState", "UnitFileState",
                  "UnitFilePreset", "FragmentPath", "DropInPaths", "Triggers", "TriggeredBy"]
    unit_states = {}
    unit_files = set()
    for unit in units:
        record = capture("unit-" + unit, ["systemctl", "show", unit] +
                         [arg for prop in properties for arg in ("-p", prop)])
        unit_states[unit] = dict(line.split("=", 1) for line in record["stdout"].splitlines()
                                 if "=" in line)
        for prop in ("FragmentPath", "DropInPaths"):
            unit_files.update(shlex.split(unit_states[unit].get(prop, "")))
    save("units.json", unit_states)
    capture("links", ["ip", "-details", "-json", "link", "show"])
    capture("packages", ["dpkg-query", "-W", "-f=${binary:Package}\t${Version}\t${db:Status-Status}\n"])
    capture("effective-modprobe", ["/usr/sbin/modprobe", "--showconfig"])
    prefix = ["sudo", "-n"] if args.sudo and os.geteuid() != 0 else []
    capture("nftables-live-json", prefix + ["/usr/sbin/nft", "-j", "list", "ruleset"])
    capture("nftables-live-text", prefix + ["/usr/sbin/nft", "-a", "-nn", "list", "ruleset"])

    sysctls = {}
    sysctl_paths = [Path("/proc/sys/net/ipv4/ip_forward")]
    # Capture every interface, including all/default, for settings touched by
    # --harden. Other keys can contain secrets or return EIO when unset.
    settings = {"ipv4": ("accept_redirects", "send_redirects", "accept_source_route",
                         "rp_filter", "log_martians"),
                "ipv6": ("accept_redirects", "accept_source_route")}
    for family, names in settings.items():
        for name in names:
            sysctl_paths.extend(sorted(Path(f"/proc/sys/net/{family}/conf").glob(f"*/{name}")))
    for path in sysctl_paths:
        try:
            sysctls[str(path)] = path.read_text().strip()
        except OSError as exc:
            errors.append({"path": str(path), "error": str(exc)})
    save("sysctl.json", sysctls)
    module_states = {module: (Path("/sys/module") / module).is_dir()
                     for module in ("dccp", "sctp", "rds", "tipc")}
    save("modules.json", module_states)
    source_files = ["/etc/os-release", "/etc/debian_version", "/etc/nftables.conf",
                    "/etc/nftables.conf.bak", "/etc/untrusted-network.nft", "/etc/sysctl.conf",
                    "/etc/sysctl.d", "/run/sysctl.d", "/usr/local/lib/sysctl.d", "/usr/lib/sysctl.d",
                    "/etc/modprobe.d", "/run/modprobe.d", "/usr/local/lib/modprobe.d", "/usr/lib/modprobe.d",
                    "/etc/systemd/system", "/run/systemd/system",
                    "/var/lib/untrusted-network-firewall", "/etc/iptables", "/etc/ufw", "/etc/firewalld"]
    # Record absent managed paths explicitly: recovery must remove newly created
    # files instead of restoring invented defaults at those paths.
    source_files.extend(["/etc/sysctl.d/99-untrusted-network.conf",
                         "/etc/modprobe.d/99-untrusted-network.conf",
                         "/etc/systemd/system/untrusted-network-firewall.service"])
    source_files.extend([str(REPO / "debian/firewall.sh"), str(REPO / "debian/firewall.md"),
                         str(Path(__file__).resolve())])
    source_files.extend(sorted(unit_files))
    inventory = {}
    with tarfile.open(destination / "configuration.tar.gz", "w:gz", dereference=False) as archive:
        for name in dict.fromkeys(source_files):
            path = Path(name)
            try:
                info = path.lstat()
                inventory[name] = {"exists": True, "mode": oct(stat.S_IMODE(info.st_mode)),
                                   "uid": info.st_uid, "gid": info.st_gid,
                                   "mtime_ns": info.st_mtime_ns,
                                   "symlink": os.readlink(path) if path.is_symlink() else None}
                archive.add(path, arcname=str(path).lstrip("/"))
            except FileNotFoundError:
                # A failure below a present directory is distinct from an absent root.
                if name in inventory:
                    errors.append({"path": name, "error": "file disappeared during archive"})
                else:
                    inventory[name] = {"exists": False}
            except OSError as exc:
                errors.append({"path": name, "error": str(exc)})
    save("paths.json", inventory)
    (destination / "loaded-modules.txt").write_text(Path("/proc/modules").read_text())
    save("commands.json", commands)
    manifest = {
        "started_utc": started, "finished_utc": datetime.now(timezone.utc).isoformat(),
        "uid": os.geteuid(), "kernel": os.uname().release,
        "network_namespace": os.readlink("/proc/self/ns/net"),
        "sysctl_values": len(sysctls), "unit_count": len(unit_states),
        "errors": errors,
        "complete": not errors,
        "notes": ["Read-only observations taken sequentially. Run before any firewall operations.",
                  "An empty output from a failed command is NOT evidence of empty state.",
                  "Restore selectively; never feed the full original ruleset to nft as an undo.",
                  "This capture alone does not make firewall.sh --disable undo --harden."]}
    save("manifest.json", manifest)
    lines = ["# Firewall baseline", "", f"Captured at {started}.", "",
             "No firewall rules, kernel settings, modules, or services were changed.", "",
             "`sysctl.json` contains exact live per-interface values; `units.json` records",
             "both running state and boot enablement. `paths.json` also records absence.",
             "`configuration.tar.gz` preserves files, symlinks, permissions, and ownership.",
             "`commands.json` records command failures as well as successful output.", "",
             "Inspect manifest.json before relying on this capture. Failed nft commands",
             "mean the live ruleset is UNKNOWN, even if nftables.service was inactive.", "",
             "Do not restore the archive wholesale or execute a saved `flush ruleset`.",
             "Restoration must target only changes made by the firewall script.", ""]
    if errors:
        lines += ["Capture is incomplete. Read manifest.json for errors.", "",
                  "From a regular terminal, before applying the firewall or hardening:", "", "```sh",
                  f"python3 {shlex.quote(str(Path(__file__).resolve()))} --sudo", "```", "",
                  "This authenticates sudo only for reading nftables. It writes a NEW snapshot",
                  "without overwriting this one or changing system configuration.", ""]
    (destination / "README.md").write_text("\n".join(lines))
    hashes = [hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name
              for path in sorted(destination.iterdir()) if path.is_file()]
    (destination / "SHA256SUMS").write_text("\n".join(hashes) + "\n")
    print(destination)
    print(f"Captured {len(sysctls)} kernel values and {len(unit_states)} unit states; {len(errors)} errors.")
    print("Snapshot complete." if not errors else "Snapshot INCOMPLETE; see manifest.json for missing data.")
    for error in errors:
        print(json.dumps(error))
    return 0 if not errors else 2


if __name__ == "__main__":
    raise SystemExit(main())
