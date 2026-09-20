# Host firewall

`firewall.sh` is optional and is not run by `run-all.sh`. It requires Debian 13,
nftables, systemd, and Python 3. The package installer includes these dependencies.

On a fresh machine, save a baseline before running `--enable` or `--harden`.
From the repository root in a regular terminal:

```sh
./debian/firewall-snapshot.py --sudo
```

The collector only reads system state. It asks for sudo authentication to read
live nftables rules and saves a new private directory under `.firewall-baselines/`
(ignored by Git). It captures the original per-interface kernel values, service
running and boot states, configuration files and symlinks, absent managed paths,
and loaded module state. Earlier snapshots are never overwritten.

The command prints the snapshot path and reports whether capture is complete.
If it exits with status 2, check `manifest.json` for missing data before making
changes. A failed ruleset inspection means unknown rules, not an empty firewall.
This snapshot preserves evidence for recovery; `--disable` still removes only
the firewall rules and does not automatically restore hardening.

For a machine that has already run the old script:

```sh
sudo ./firewall.sh --enable
sudo ./firewall.sh --harden
sudo ./firewall.sh --status
```

Run the commands in order and stop if one fails. There is no need to disable the
old firewall first. Review the switches near the top before enabling features.

## Firewall controls

- `-h` or `--help` explains the commands and shows the configured preferences.
  It needs no sudo and makes no changes.
- `--enable` checks the rules, loads them atomically, and enables the dedicated
  `untrusted-network-firewall.service` for boot. Repeat it after changing
  firewall preferences.
- `--disable` stops that dedicated service and removes only
  `table inet untrusted_network`. It never stops the shared nftables service,
  flushes other tables, changes kernel settings, starts services, or deletes
  recovery records.
- `--status` reports service states and redirect settings. With sudo it also
  reads the actual rules. Failed inspection is reported as unknown.
- `--harden` separately applies persistent kernel settings, module-loading
  restrictions, automatic security updates, NetworkManager startup, and the
  printing/Bluetooth service preferences. The package installer only installs
  packages; run `--harden` separately to apply this configuration. These changes
  remain when the firewall is disabled; this is deliberate, not an undo command.

The default firewall blocks new inbound connections to the host on all
interfaces, including VPN interfaces. Loopback, established/related connections,
DHCP, and selected ICMP/ICMPv6 traffic are allowed.

Private-address and multicast outbound blocking applies only to
`UNTRUSTED_INTERFACES`. The defaults match typical Debian Wi-Fi, Ethernet, USB,
and mobile interface names. Add custom physical-interface names to the list.
VPN interfaces and container bridges normally do not match these prefixes.
This list is a naming convention, not automatic detection of trusted networks.

Forwarded replies are allowed, and new forwarded traffic arriving on the
untrusted interfaces is dropped. Container/VM traffic originating on other
interfaces can still be forwarded, subject to other firewalls and kernel routing
settings. Outbound LAN isolation applies to host processes, not every container.

`ALLOW_LOCAL_NETWORK=yes` removes outbound LAN blocking without opening host
inbound ports. This is useful for a router admin page, NAS, or captive portal.

`ALLOW_PRINTING=yes` permits discovery on the untrusted interfaces and outgoing
TCP ports 515, 631, and 9100. Other local-network restrictions remain. These are
port exceptions, not a trusted-printer allowlist. Run `--enable` to update rules
and `--harden` to enable CUPS and discovery services.

`ALLOW_BLUETOOTH` affects only `--harden`. Bluetooth is not filtered by nftables.
Hardening stops and disables unwanted services; a later administrator action,
dependency, or activation mechanism may still start a disabled service.

## Operation history

Privileged `--enable`, `--disable`, and `--harden` invocations automatically append
to a private log, starting with the first invocation of this version:

```sh
sudo less /var/log/untrusted-network-firewall/history.log
```

Each run records UTC start/end times, a run identifier, the invoking user,
preferences, the script checksum, executed commands, console output and errors,
and the final exit code. Before/after observations record service states, the
managed live firewall table, and per-interface kernel settings. File replacements
also record their previous contents (or absence) and requested contents. Failed
observations are labeled incomplete; the log does not infer missing values.

The directory is mode `0700` and the file is mode `0600`. History is appended,
never truncated or removed by `--disable`; no automatic rotation discards older
runs. If logging cannot be initialized, the operation stops before changing the
firewall. A failure writing output makes the command return failure even if some
changes already took effect. A run without an `END` entry may have been interrupted.
Invalid arguments, missing logging dependencies, and calls without required sudo
privileges are rejected before logging. Help and status do not write to the log.

This records script operations, not individual network packets or changes made
by other programs. Service activity at boot or through direct `systemctl` commands
is available in the systemd journal (subject to its retention settings):

```sh
sudo journalctl -u untrusted-network-firewall.service
```

Keep the original baseline snapshot too: the operation log supplements it and
does not implement automatic restoration of hardening.

## Migration and recovery

The first `--enable` recognizes the old script's generated configuration.
Unrecognized edits, missing original backups, or missing saved state stop
migration rather than silently replacing an unknown setup.

Migration archives the old configuration, its original backup, kernel/module
files, and saved state under:

```text
/var/lib/untrusted-network-firewall/legacy-backup/
```

It also retains the original `/etc/nftables.conf.bak` and the old `sysctl` and
`units` records. The snapshot is not overwritten on subsequent runs.

The new rules go in `/etc/untrusted-network.nft`; the unit goes in
`/etc/systemd/system/untrusted-network-firewall.service`. Only after these rules
are loaded and the dedicated service is enabled does migration copy the original
configuration back to `/etc/nftables.conf`. It does not execute the restored file,
reload the shared service, or change that service's enablement. At boot the new
service is ordered after nftables and before network setup. It follows shared
nftables service reloads and restarts so those operations reload this policy too.
Stopping the dedicated service does not stop the shared one; these dependencies
are one-way. See [systemd unit dependencies](https://manpages.debian.org/trixie/systemd/systemd.unit.5.en.html).

The old script never recorded per-interface kernel values, whether services
were running, or nftables' original boot state. Exact automatic restoration is
therefore impossible. The new version preserves the records for deliberate
recovery instead of manufacturing missing values. Applying `--harden` declares
the desired settings going forward; it does not create a pretend original state.

No reboot is required to enable filtering. After a later reboot, use sudo
`--status` to verify the loaded table and the dedicated service's active state.
Other firewall managers or an administrator directly flushing the whole ruleset can
still remove these rules. Reload the dedicated service or rerun `--enable` if
that happens. Do not reload an old backup containing `flush ruleset` as an undo.

## Limits

The firewall does not authenticate DHCP, DNS, ARP, or IPv6 routers. It permits
necessary control traffic, and public-address neighbors remain reachable
outbound. It does not encrypt traffic, prevent malware from connecting to public
addresses, or make a compromised router trustworthy. Use authenticated encrypted
protocols and keep the operating system and applications updated.
