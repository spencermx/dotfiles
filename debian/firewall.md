# Host firewall

`firewall.sh` is optional and is not run by `run-all.sh`. It requires Debian 13,
nftables, systemd, and Python 3. The package installer includes these dependencies.

For a machine that has already run the old script:

```sh
sudo ./firewall.sh --enable
sudo ./firewall.sh --harden
sudo ./firewall.sh --status
```

Run the commands in order and stop if one fails. There is no need to disable the
old firewall first. Review the switches near the top before enabling features.

## Firewall controls

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
  restrictions, and the printing/Bluetooth service preferences. These changes
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

## Verification

```sh
python3 -m unittest discover -s debian/tests -v
python3 debian/tests/check_firewall_network.py
```

The first command uses temporary files and simulated system tools to check
migration, backup retention, repeated operation, and failure handling. It needs
no privileges.

The second command creates disposable user and network namespaces and sends
real IPv4/IPv6 packets between test interfaces. It checks filtering, replies,
printer discovery, container forwarding, tunnel interface scope, and preservation
of unrelated tables. It needs permission to create user namespaces, but does not
change the machine's live firewall or services.
