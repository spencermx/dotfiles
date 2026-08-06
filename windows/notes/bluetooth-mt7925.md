# Bluetooth: MT7925 (RZ717) — working on both OSes; cause not fully isolated

Bluetooth works as of 2026-08-06. The hardware is fine — no reseat, no BIOS
update, no driver change, nothing to wait on upstream.

**Two changes were made in the same session and the variables were not
isolated.** Either could be the fix. Recorded honestly here so the next person
(me) does not build on a story that was never tested.

## What was changed

1. **Removed the failing devnode**, then rescanned:

   ```powershell
   pnputil /remove-device "USB\VID_0000&PID_0002\<instance>&0&12"
   pnputil /scan-devices
   ```

   This deletes Windows' PnP entry for the unidentified device on port 12 —
   the "Unknown USB Device (Device Descriptor Request Failed)" row. Equivalent
   to Device Manager → Uninstall device → Scan for hardware changes. It
   uninstalls no drivers and touches no files; Windows regenerates the entry
   on detection. It came straight back, still broken, at the time.

2. **Disabled Fast Startup:**

   ```powershell
   Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
     -Name HiberbootEnabled -Value 0 -Type DWord
   ```

Then a Restart. Bluetooth came back with all paired devices intact.

## Why the cause is ambiguous

`Kernel-Boot` event 27 records the boot type: `0x0` full, `0x1` hybrid.

```
8/1  07:17:54   0x0  full     -> BT arrived 07:18:02        works
8/6  08:56:21   0x1  hybrid                                 broken
8/6 "21:28:45"  0x0  full     <- Fast Startup still ON      broken
8/6  15:41:16   0x1  hybrid   <- a "reboot" that was not    broken
8/6  15:46:15   0x0  full     -> BT arrived 15:46:22        works
```

The third line is the problem for the tidy explanation. It is a genuine full
boot, with Fast Startup still enabled, that did **not** fix Bluetooth. It also
followed an unexpected shutdown (`Kernel-Power 41`), so no hibernation image
was written — meaning a clean, hiberfil-free full boot had already failed.

That removes most of the basis for blaming Fast Startup. The only thing that
differed by the successful boot was change 1, the devnode removal. So a stale
placeholder devnode plus a full re-enumeration is at least as good an
explanation, and arguably better.

Note also that those `21:28` timestamps sit ~6h ahead of the wall clock that
day — the system clock jumped backward at some point. Do not trust event
ordering here without checking.

If this recurs, isolate it: change one thing, boot, check, repeat.

## Fast Startup mechanics (true regardless of whether it was the cause)

Fast Startup ("hybrid boot") does not shut the machine down. It hibernates the
kernel session to `hiberfil.sys` and restores it on power-on. A device wedged
when that image is written comes back wedged on every subsequent start.

**Cutting PSU power does not defeat it.** The image is on disk, not in RAM.
Pulling the plug for 15 seconds or 15 hours changes nothing — the next
power-on resumes the same saved session. The earlier version of this note
logged a PSU-off cold boot as having "ruled out" Fast Startup; that test never
exercised it.

Only these produce a full `0x0` init:

- **Restart** (bypasses Fast Startup; a *shutdown* does not)
- Shift-click Shut Down
- `HiberbootEnabled = 0`

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=27} -MaxEvents 5 |
  Select-Object TimeCreated, Message      # 0x0 = full, 0x1 = hybrid
```

`(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` also does not advance
across a hybrid boot.

Keep it off on this machine regardless: it leaves NTFS volumes hibernated
rather than cleanly unmounted, so Arch will refuse them or mount read-only,
and forcing a mount in that state corrupts them.

## How the failure presented

Two devnodes at one location — the real one absent, a placeholder present and
failing:

```
RZ717 Bluetooth(R) Adapter                     IsPresent = False
  USB\VID_0E8D&PID_0717&MI_00        Port_#0012

Unknown USB Device (Device Descriptor Request Failed)   IsPresent = True
  USB\VID_0000&PID_0002\...&0&12     Port_#0012    ProblemCode = 43
```

`VID_0000&PID_0002` is what Windows substitutes when it cannot read a device's
USB descriptor at all. Same root hub, same port, identical ACPI path
(`_SB.PCI0.GPP7.UP00.DP60.XH00.RHUB.POTC`).

PnP timestamps showed it had worked for ten months and stopped dead:

```
FirstInstallDate  2025-09-29   (day of the Windows install)
LastArrivalDate   2026-08-01 07:18:02   -> after the fix, 2026-08-06 15:46:22
```

## Things that were established, and hold up

- **Bluetooth is USB-attached, not PCIe.** Hardware ID
  `USB\VID_0E8D&PID_0717&MI_00`. The earlier theory that Linux lacks any
  MediaTek-BT-over-PCIe driver was irrelevant — that is not how this is wired.
- **btusb needs no changes.** Compatible ID `Class_e0&SubClass_01&Prot_01` is
  exactly btusb's generic match
  `USB_VENDOR_AND_INTERFACE_INFO(0x0e8d, 0xe0, 0x01, 0x01)`.
- **Wi-Fi working said nothing about Bluetooth.** On M.2 Key-E they are
  independent interfaces on one connector — Wi-Fi on the PCIe pins, Bluetooth
  on the USB 2.0 pins. Asymmetric Wi-Fi-OK / BT-dead looked like a seating
  fault and was not.
- **The `error -71` dismissal was wrong.** The earlier note waved off Linux's
  `usb 3-7: device descriptor read/64, error -71` because the kernel reported
  low-speed and "BT is never low-speed." Speed is read from line state
  *before* any descriptor exchange, so it is exactly the field that reads out
  wrong when a link will not train. Windows showed the same class of failure
  at the same port. Strong inference that it was the Bluetooth, though not
  directly proven.

## Arch: works, as of 2026-08-06 16:14

Whatever fixed Windows fixed Arch too. Stock kernel 7.1.5, stock btusb, no
patch, no DKMS, no module options. Scanning finds real devices; A2DP sink and
source and Handsfree profiles are all present.

```
usb 3-7: new high-speed USB device number 2
usb 3-7: New USB device found, idVendor=0e8d, idProduct=0717
Bluetooth: hci0: Device setup in 18150020 usecs
Controller D8:B3:2F:44:73:CA (public)   Powered: yes
```

This also settles the `error -71` question: `3-7` is the Bluetooth. It is the
same port that used to fail, now enumerating clean at high speed with the right
IDs. The low-speed reading was the symptom, not evidence against.

The still-unanswered question stays unanswered — devnode removal vs Fast
Startup, still not isolated, and now both are in place so there is nothing left
to separate them with short of deliberately re-breaking it.

### Init is marginal — expect the occasional bad boot

The first Arch boot after the Windows fix brought the device up but failed to
initialise it:

```
Bluetooth: hci0: Execution of wmt command timed out
Bluetooth: hci0: Failed to send wmt func ctrl (-110)
```

`hci0` existed, `rfkill` listed it, `bluetoothctl` said "No default controller
available". The next boot succeeded — but took **18 seconds** to set up, which
is `btmtk`'s internal one-shot retry (`BTMTK_FIRMWARE_DL_RETRY` ->
`btmtk_reset_sync`) working rather than a clean first pass.

So the firmware download succeeds and the `FUNC_CTRL` immediately after it is
what's flaky. That is a known upstream bug: the BT core re-arms sleep
protection once the firmware is running, so the next WMT command gets no
answer. Register `0x18011100` bit 1 controls it.

Not in mainline — checked `torvalds/linux` HEAD on 2026-08-06 (7.2-rc6 era),
no `0x18011100` anywhere in `drivers/bluetooth/`. A patch was posted to
linux-bluetooth on 2026-05-31 ("Bluetooth: btmtk: Fix MT7925 WMT command
timeout due to sleep protection") and has not landed.

If bad boots become frequent, the fix is small and self-contained: write that
register before the firmware download and again before `FUNC_CTRL`, using the
existing `btmtk_usb_uhw_reg_write()` (`drivers/bluetooth/btmtk.c:779`). The
call site to wrap is the `case 0x7925:` arm of `btmtk_usb_setup()`, around
`btmtk.c:1371-1417`. Ship it as DKMS so it survives kernel updates and comes
straight back out when upstream lands the real one. Until then a reboot is the
cheaper fix.

### Do not try to recover it with a USB rebind

Unbinding and rebinding `btusb` to force a re-probe **wedges the device**:

```
usb 3-7: device not accepting address 2, error -71
usb 3-7: USB disconnect, device number 2
usb 3-7: device descriptor read/64, error -110
```

It then disappears from `lsusb` entirely and does not come back on its own.
Tried on 2026-08-06; only a power cycle recovered it. The radio does not
survive a USB-level reset in this state, so there is no iterating on it live —
any fix has to be in place *before* the first probe at boot, one attempt per
boot. Same applies to `usbreset` and to unbind/rebind of the xHCI controller.

## Hardware reference

```
RZ717 Bluetooth(R) Adapter
  Hardware Ids  USB\VID_0E8D&PID_0717&REV_0100&MI_00
  Compatible    USB\Class_e0&SubClass_01&Prot_01
  Service       BTHUSB
  Driver        1.1043.0.550, Mediatek Inc., 2025-07-16

Location      Port_#0012
Location path PCIROOT(0)#PCI(0201)#PCI(0000)#PCI(0C00)#PCI(0000)#USBROOT(0)#USB(12)
Controller    PCI\VEN_1022&DEV_43FD  "AMD USB 3.20 xHCI 1.10",
              PCI bus 18 (0x12), dev 0, fn 0, subsys 1b21:1142
```

On a *chipset* xHCI behind the Promontory 21 PCIe switch (`UP00`/`DP60` in the
ACPI path), not either CPU-attached controller. Wi-Fi is separate:
`PCI\VEN_14C3&DEV_0717`. Board is ASRock X870E Nova WiFi, BIOS AMI 3.40
(2025-08-26) — never updated, and it did not turn out to matter.

## Unrelated, but noticed

`Kernel-Power 41` "rebooted without cleanly shutting down" with `EventLog 6008`
unexpected-shutdown on 2026-02-11, 2026-08-01 and 2026-08-06. The machine has
been hanging or losing power intermittently. Worth watching separately.
