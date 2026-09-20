#!/usr/bin/env python3
"""Exercise complete script operations with temporary files and fake system tools.

No root, live services, kernel settings, or live packet filtering are touched.
The separate network test uses real nftables in isolated network namespaces.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "firewall.sh"
FIXTURE = Path(__file__).parent / "fixtures/firewall-v1.nft"
UNIT = "untrusted-network-firewall.service"

STUB = r'''#!/usr/bin/python3
import glob, json, os, pathlib, re, sys
root = pathlib.Path(os.environ["FIREWALL_TEST_ROOT"])
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_file = root / "backend.json"
state = json.loads(state_file.read_text())
with (root / "calls.jsonl").open("a") as out:
    out.write(json.dumps([tool] + args) + "\n")
def save():
    state_file.write_text(json.dumps(state))
def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)
def load_rules(path):
    text = pathlib.Path(path).read_text()
    owner = re.search(r'comment "(untrusted-network-firewall-v2)"', text)
    entries = [{"table": {"family": "inet", "name": "untrusted_network",
                           "comment": owner.group(1) if owner else ""}}]
    for name, hook, policy in re.findall(
            r"chain (\w+) \{\s*type filter hook (\w+) priority filter; policy (\w+);", text):
        entries.append({"chain": {"family": "inet", "table": "untrusted_network",
                                  "name": name, "hook": hook, "policy": policy, "type": "filter"}})
    state["tables"]["untrusted_network"] = entries
    state["last_rules"] = text
    save()
if tool == "id":
    print(os.environ.get("FIREWALL_TEST_UID", "0"))
elif tool == "systemd-analyze":
    if os.environ.get("FAIL_UNIT_CHECK"):
        fail("unit validation failed")
elif tool == "nft":
    if args[:3] == ["-j", "list", "ruleset"]:
        if os.environ.get("FAIL_INSPECTION"):
            fail("cannot inspect netlink")
        print(json.dumps({"nftables": sum(state["tables"].values(), [])}))
    elif "-f" in args:
        if "-c" in args:
            if os.environ.get("FAIL_RULE_CHECK"):
                fail("invalid rules")
        else:
            if os.environ.get("FAIL_RULE_LOAD"):
                fail("failed rule transaction")
            load_rules(args[args.index("-f") + 1])
    elif args[:3] == ["destroy", "table", "inet"]:
        state["tables"].pop(args[3], None)
        save()
    elif args[:2] == ["list", "table"]:
        print(state.get("last_rules", "legacy table"))
    else:
        fail("unexpected nft operation: " + repr(args))
elif tool == "systemctl":
    verb = args[0]
    units = [a for a in args[1:] if a.endswith((".service", ".socket", ".path"))]
    if os.environ.get("FAIL_SYSTEMCTL") == verb:
        fail("simulated systemctl " + verb + " failure")
    if verb == "daemon-reload":
        pass
    elif verb == "show":
        unit = units[0]
        defaults = {"LoadState": "not-found", "ActiveState": "inactive", "UnitFileState": ""}
        values = state["units"].get(unit, defaults)
        props = [args[i+1] for i, a in enumerate(args) if a == "-p"]
        for prop in props:
            value = values[prop]
            print(value if "--value" in args else prop + "=" + value)
    elif verb in ("is-enabled", "is-active"):
        values = state["units"].get(units[0], {})
        key = "UnitFileState" if verb == "is-enabled" else "ActiveState"
        want = "enabled" if verb == "is-enabled" else "active"
        sys.exit(0 if values.get(key) == want else 1)
    elif verb in ("enable", "disable", "start"):
        for unit in units:
            values = state["units"].setdefault(unit, {
                "LoadState": "loaded", "ActiveState": "inactive", "UnitFileState": "disabled"})
            if verb in ("enable", "disable"):
                values["UnitFileState"] = "enabled" if verb == "enable" else "disabled"
            if "--now" in args or verb == "start":
                values["ActiveState"] = "inactive" if verb == "disable" else "active"
            if unit == "untrusted-network-firewall.service":
                if verb == "start":
                    load_rules(root / "etc/untrusted-network.nft")
                elif verb == "disable" and "--now" in args:
                    state["tables"].pop("untrusted_network", None)
            if unit == "nftables.service" and verb == "disable" and "--now" in args:
                state["tables"] = {}
        save()
    else:
        fail("unexpected systemctl operation: " + repr(args))
elif tool == "sysctl":
    if args[0] != "-p":
        fail("must apply only the managed sysctl file")
    if os.environ.get("FAIL_SYSCTL"):
        fail("sysctl failed")
    for line in pathlib.Path(args[1]).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        pattern = str(root / "proc/sys" / key.replace(".", "/"))
        for path in glob.glob(pattern):
            pathlib.Path(path).write_text(value + "\n")
else:
    fail("unexpected tool: " + tool)
'''

class FirewallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="firewall-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ("etc/systemd/system", "etc/sysctl.d", "etc/modprobe.d",
                          "var/lib/untrusted-network-firewall", "run/lock", "bin", "tmp"):
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        self.script = self.root / "firewall.sh"
        text = SOURCE.read_text()
        text = text.replace("export PATH=/usr/sbin:/usr/bin:/sbin:/bin",
                            f"export PATH={self.root}/bin:/usr/sbin:/usr/bin:/sbin:/bin")
        for path in ("/etc/", "/var/lib/", "/run/lock/", "/proc/sys/", "/sys/module/"):
            text = text.replace(path, str(self.root) + path)
        self.script.write_text(text)
        stub = self.root / "bin/stub"
        stub.write_text(STUB)
        stub.chmod(0o755)
        for command in ("id", "nft", "systemctl", "sysctl", "systemd-analyze"):
            (self.root / "bin" / command).symlink_to(stub)
        units = ["nftables.service", "cups.service", "cups.socket", "cups.path",
                 "cups-browsed.service", "avahi-daemon.service", "avahi-daemon.socket",
                 "ModemManager.service", "bluetooth.service"]
        self.original = {
            "tables": {"other_firewall": [{"table": {"family": "inet", "name": "other_firewall"}}]},
            "units": {u: {"LoadState": "loaded", "UnitFileState": "enabled",
                          "ActiveState": "active"} for u in units}}
        self.set_state(self.original)
        self.main_conf = self.root / "etc/nftables.conf"
        self.main_conf.write_text("# administrator configuration\n")
        for family in ("ipv4", "ipv6"):
            for interface in ("all", "default", "lo", "eth0"):
                for setting in ("accept_redirects", "send_redirects", "accept_source_route", "rp_filter", "log_martians"):
                    path = self.root / f"proc/sys/net/{family}/conf/{interface}/{setting}"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("1\n")
        self.env = dict(os.environ, FIREWALL_TEST_ROOT=str(self.root), TMPDIR=str(self.root / "tmp"))

    def set_state(self, state):
        (self.root / "backend.json").write_text(json.dumps(state))

    def state(self):
        return json.loads((self.root / "backend.json").read_text())

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_script(self, *args, success=True, **env):
        result = subprocess.run(["bash", str(self.script), *args],
                                env=dict(self.env, **env), capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def legacy(self):
        self.main_conf.write_text(FIXTURE.read_text())
        Path(str(self.main_conf) + ".bak").write_text("flush ruleset\n# original configuration\n")
        state_dir = self.root / "var/lib/untrusted-network-firewall"
        (state_dir / "sysctl").write_text("net.ipv4.conf.all.accept_redirects 1\n")
        (state_dir / "units").write_text("cups.service enabled\n")
        for path in ("etc/sysctl.d/99-untrusted-network.conf", "etc/modprobe.d/99-untrusted-network.conf"):
            (self.root / path).write_text("# Written by debian/firewall.sh --enable\n# original hardening\n")
        state = self.state()
        state["tables"]["untrusted_network"] = [{"table": {"family": "inet", "name": "untrusted_network"}}]
        self.set_state(state)

    def test_enable_then_disable_preserves_other_firewall_and_services(self):
        self.run_script("--enable")
        self.assertIn("untrusted_network", self.state()["tables"])
        self.run_script("--disable")
        self.run_script("--disable")
        state = self.state()
        self.assertEqual(state["tables"], self.original["tables"])
        for unit, value in self.original["units"].items():
            self.assertEqual(state["units"][unit], value)
        self.assertEqual(self.main_conf.read_text(), "# administrator configuration\n")

    def test_migrate_retains_old_backups_and_never_restarts_shared_service(self):
        self.legacy()
        backup = Path(str(self.main_conf) + ".bak").read_bytes()
        records = self.root / "var/lib/untrusted-network-firewall"
        old = {p.name: p.read_bytes() for p in records.iterdir()}
        old_rules = self.main_conf.read_bytes()
        self.run_script("--enable")
        self.assertEqual(self.main_conf.read_bytes(), backup)
        self.assertEqual(Path(str(self.main_conf) + ".bak").read_bytes(), backup)
        for name, data in old.items():
            self.assertEqual((records / name).read_bytes(), data)
        self.assertEqual((records / "legacy-backup/nftables.conf.v1").read_bytes(), old_rules)
        self.run_script("--enable")
        self.run_script("--disable")
        self.assertIn("other_firewall", self.state()["tables"])
        self.assertFalse(any(c[0] == "systemctl" and "nftables.service" in c for c in self.calls()))
        self.assertFalse(any(c[0] == "sysctl" for c in self.calls()))

    def test_legacy_disable_and_harden_require_safe_migration(self):
        for action in ("--disable", "--harden"):
            with self.subTest(action=action):
                self.legacy()
                before = self.state()
                conf = self.main_conf.read_bytes()
                self.run_script(action, success=False)
                self.assertEqual(self.state(), before)
                self.assertEqual(self.main_conf.read_bytes(), conf)

    def test_modified_legacy_rules_require_manual_merge(self):
        self.legacy()
        self.main_conf.write_text(self.main_conf.read_text().replace("policy drop;", "policy accept;", 1))
        before = self.state()
        self.run_script("--enable", success=False)
        self.assertEqual(self.state(), before)
        self.assertFalse((self.root / "etc/untrusted-network.nft").exists())

    def test_missing_legacy_backup_does_not_change_live_rules(self):
        self.legacy()
        Path(str(self.main_conf) + ".bak").unlink()
        before = self.state()
        self.run_script("--enable", success=False)
        self.assertEqual(self.state(), before)

    def test_rule_validation_failure_precedes_installation(self):
        self.legacy()
        before = self.main_conf.read_bytes()
        state = self.state()
        self.run_script("--enable", success=False, FAIL_RULE_CHECK="1")
        self.assertEqual(self.main_conf.read_bytes(), before)
        self.assertEqual(self.state(), state)
        self.assertFalse((self.root / "etc/untrusted-network.nft").exists())

    def test_failed_startup_enable_preserves_legacy_recovery_and_live_rules(self):
        self.legacy()
        before = self.state()
        old_config = self.main_conf.read_bytes()
        self.run_script("--enable", success=False, FAIL_SYSTEMCTL="enable")
        self.assertEqual(self.state(), before)
        self.assertEqual(self.main_conf.read_bytes(), old_config)
        self.assertTrue((self.root / "var/lib/untrusted-network-firewall/legacy-backup/units").exists())

    def test_failed_load_keeps_previous_rules(self):
        self.run_script("--enable")
        before = self.state()["tables"]
        self.run_script("--enable", success=False, FAIL_RULE_LOAD="1")
        self.assertEqual(self.state()["tables"], before)

    def test_inspection_failure_is_not_absence_or_success(self):
        self.run_script("--enable")
        before = self.state()
        self.run_script("--disable", success=False, FAIL_INSPECTION="1")
        self.assertEqual(self.state(), before)
        result = self.run_script("--status", success=False, FAIL_INSPECTION="1")
        self.assertIn("protection is unknown", result.stderr)

    def test_failed_service_stop_keeps_firewall(self):
        self.run_script("--enable")
        self.run_script("--disable", success=False, FAIL_SYSTEMCTL="disable")
        self.assertIn("untrusted_network", self.state()["tables"])

    def test_fresh_disable_does_not_start_or_change_anything(self):
        before = self.state()
        self.run_script("--disable")
        self.assertEqual(self.state(), before)

    def test_invalid_choices_do_not_prevent_disable(self):
        self.run_script("--enable")
        self.script.write_text(self.script.read_text().replace("ALLOW_LOCAL_NETWORK=no", "ALLOW_LOCAL_NETWORK=typo"))
        self.run_script("--enable", success=False)
        self.run_script("--disable")
        self.assertNotIn("untrusted_network", self.state()["tables"])

    def test_unknown_table_and_unmanaged_files_are_not_overwritten(self):
        state = self.state()
        state["tables"]["untrusted_network"] = [{"table": {"family": "inet", "name": "untrusted_network"}}]
        self.set_state(state)
        self.run_script("--enable", success=False)
        self.run_script("--disable", success=False)
        self.assertEqual(self.state(), state)
        self.set_state(self.original)
        rules = self.root / "etc/untrusted-network.nft"
        rules.write_text("# belongs to another program\n")
        self.run_script("--enable", success=False)
        self.assertEqual(rules.read_text(), "# belongs to another program\n")

    def test_hardening_is_explicit_and_disable_never_reverts_it(self):
        self.run_script("--enable")
        key = self.root / "proc/sys/net/ipv4/conf/eth0/accept_redirects"
        self.assertEqual(key.read_text(), "1\n")
        self.run_script("--harden")
        self.assertEqual(key.read_text(), "0\n")
        settings = self.root / "etc/sysctl.d/99-untrusted-network.conf"
        self.assertIn("net.ipv6.conf.*.accept_redirects = 0", settings.read_text())
        self.run_script("--disable")
        self.assertEqual(key.read_text(), "0\n")
        self.assertEqual(self.state()["units"]["cups.service"]["ActiveState"], "inactive")
        self.assertTrue(settings.exists())
        self.assertTrue(all(c[1] == "-p" for c in self.calls() if c[0] == "sysctl"))

    def test_service_failure_returns_failure_and_does_not_remove_firewall(self):
        self.run_script("--enable")
        self.run_script("--harden", success=False, FAIL_SYSTEMCTL="disable")
        self.assertIn("untrusted_network", self.state()["tables"])

    def test_sysctl_failure_is_not_success(self):
        self.run_script("--enable")
        self.run_script("--harden", success=False, FAIL_SYSCTL="1")
        self.assertIn("untrusted_network", self.state()["tables"])

    def test_status_is_read_only(self):
        self.run_script("--enable")
        before = self.state()
        self.run_script("--status")
        self.assertEqual(self.state(), before)

    def test_extra_arguments_rejected_before_changes(self):
        self.run_script("--enable", "unexpected", success=False)
        self.assertEqual(self.state(), self.original)

if __name__ == "__main__":
    unittest.main()
