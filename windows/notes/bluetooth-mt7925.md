# Bluetooth: MT7925 (RZ717) — what to check from Windows

Bluetooth does not work on Arch on the desktop (ASRock X870E Nova WiFi,
kernel 7.1.5). It works on Windows on the same machine, so the hardware is
fine. The radio is simply never presented to Linux on any bus, so no driver
has anything to attach to.

Read the "already ruled out" list before re-testing anything -- all of it was
checked on 2026-08-06 and came back negative.

## The check to run in Windows

Device Manager -> Bluetooth -> the MediaTek adapter -> Properties ->
Details tab -> pick "Hardware Ids" from the dropdown.

Write down what it starts with. That single string decides everything:

| Hardware Id starts with | What it means |
| --- | --- |
| `USB\VID_0E8D&PID_...` | BT is USB-attached. Linux *should* see it. Something board-level is gating that internal USB port under Linux only. Worth chasing. |
| `PCI\VEN_14C3...` | BT is PCIe-attached. Linux has no driver for MediaTek BT over PCIe at all -- `drivers/bluetooth/` has btusb, btmtkuart, btmtksdio, and no PCIe variant. Explains every symptom. Nothing to do but wait for upstream. |

While in Device Manager, also grab:

- The adapter's **Location** field (same Details dropdown) -- says which bus
  and port it hangs off.
- Driver tab -> **Driver Version / Provider**. If MediaTek ships a version
  much newer than what Linux has, that tells us how far behind upstream is.

## Already ruled out (do not redo)

Hardware and firmware:

- Hardware is good -- works in Windows.
- BIOS "BT On/Off" set from Auto to Enabled, saved, rebooted. No change.
- True cold boot with PSU switched off ~15s. No change.
- Windows Fast Startup leaving the chip half-initialised. Cold boot
  disproved it.

Linux side:

- `lspci` shows exactly ONE function on the card, `08:00.0` = Wi-Fi
  (`14c3:0717`). There is no second PCI function for BT.
- No MediaTek USB device (`0e8d:*`) has ever appeared, on any bus, on any
  boot.
- `/sys/class/bluetooth` never exists. `rfkill` lists Wireless LAN only.
- Zero Bluetooth lines in `journalctl -k -b`, ever. The kernel never even
  tries.
- Firmware IS present: `/usr/lib/firmware/mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin.zst`
- Driver IS present and complete: `btusb.c` + `btmtk.c` handle chip id
  `0x7925` and reference that exact firmware file. `btusb.c` also matches
  MediaTek BT generically via
  `USB_VENDOR_AND_INTERFACE_INFO(0x0e8d, 0xe0, 0x01, 0x01)`, so a missing
  device ID is not the problem.
- The Wi-Fi driver (`mt76/mt7925/`) contains no BT code at all, by design.
  On this chip BT is a separate USB function, not something Wi-Fi enables.
- Runtime PM / deep sleep on the shared CONNINFRA power domain: set
  `deep-sleep` to 0 via debugfs and force-re-enumerated the xHCI controller.
  No change. (`mt7925/init.c` does disable runtime PM for MT7927 because it
  "crashes BT firmware on the shared CONNINFRA domain" -- MT7925 is outside
  that guard, but pinning it awake changed nothing.)

Red herring, ignore it:

- `usb 3-7: device descriptor read/64, error -71` at every boot. It is NOT
  the Bluetooth. The kernel detects it as **low-speed (1.5 Mbit/s)** and BT
  adapters are never low-speed -- they are full- or high-speed. Some other
  flaky port or internal header. An ASRock forum thread for this same board
  mentions the same port and error next to BT complaints, which is what made
  it look relevant. It is not.

## If it turns out to be USB-attached

Then the port exists but is not enumerating under Linux. Next things to try,
in rough order of cost:

1. BIOS update -- current version was never checked against ASRock's latest.
2. `usbcore.autosuspend=-1` on the kernel command line.
3. Compare the Windows Location field against the Linux USB topology to work
   out which internal port it should be on, then check whether that port is
   dead for everything or just for this.

## Fallback

A USB Bluetooth dongle works immediately -- `btusb` is already installed and
handles standard dongles with no configuration. The onboard radio is worth
revisiting in a few months; MediaTek Wi-Fi 7 Bluetooth support is visibly
still landing upstream (the MT7927/MT6639 series merged around March-June
2026).
