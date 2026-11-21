# Nvmon

![Nvmon showing an RTX 3060 at PCIe Gen 3](docs/screenshot.png)

Watches one NVIDIA GPU on an Omarchy desktop. It was built while chasing an
RTX 3060 that kept falling off the PCIe bus (Xid 79), and it answers the
questions that came up: what speed is the PCIe link at, has it been changing
speed, is the card idle or awake, how hot is it, is the fan turning, and has
the kernel logged an Xid error since boot.

- **Stability badge**: how long the GPU has run without an Xid error, counted
  from boot or from the last error. It turns red when an Xid shows up or the
  GPU is lost.
- **PCIe link**: current generation and width against the maximum, with a
  step chart of the last five minutes and the number of speed changes in it.
  It is in the accent color at full speed and yellow at idle speed.
- **Temperature, fan, power, memory**: each with a level bar and a chart of
  the last five minutes. Temperature also shows its peak.
- **Performance state** (P2 awake, P8 idle), GPU and encoder load.
- **Keepalive**: whether the
  [`rtx-keepalive.service`](https://github.com/franzejr/rtx-keepalive) user
  unit is running and for how long, with a button to start or stop it.
  Stopping asks first. Without the unit installed, the card shows "Not
  installed".
- **Processes on the GPU.**

It reads everything through `nvidia-smi`, `journalctl`, and `systemctl --user`,
and needs no root. If `nvidia-smi` is missing or the GPU is lost, the window
says so. The charts start empty and fill over the first five minutes; nothing
is kept between runs.

Nvmon only watches. It does not keep the GPU awake itself, and closing it
changes nothing. Its two-second `nvidia-smi` queries do not wake the card
either: an idle card still reads P8 and Gen 1 through them.

## The problem it was built for

The machine: an RTX 3060 (12 GB) in the second CPU slot (PCIEX8, so the link
runs at x8) of a Gigabyte Z370 AORUS Gaming 5 with BIOS F15 and an
i7-8700K. The monitor is plugged into the Intel integrated graphics, so the
NVIDIA card sits idle most of the time and only wakes for CUDA, NVENC and
similar work.

From 4 November 2026 the card kept disappearing with this in the kernel log:

```
NVRM: Xid (PCI:0000:02:00): 79, GPU has fallen off the bus.
NVRM: Xid (PCI:0000:02:00): 154, GPU recovery action changed from 0x0 (None) to 0x2 (OS Reboot)
```

Xid 79 means the driver lost contact with the card over PCI Express; only a
reboot brings it back. It happened nine times in two weeks, always with the
card idle, anywhere from 2 minutes to 9 hours after boot and usually within
3 hours.

### What was ruled out

| Suspect | Test | Result |
|---|---|---|
| Kernel | 7.2.15, 7.2.8 and 6.18 LTS | Failed on all three |
| NVIDIA driver | 615.78.08 and 610.57.04 (open modules) | Failed on both |
| ASPM (PCIe link power saving) | `lspci -vv` on the card and its root port | "ASPM Disabled" on both sides |
| Temperature | Readings around the failures | The card failed cold, at idle (~35 °C, 7 W) |
| System suspend | Journal of every failing boot | No suspend in any of them |
| PCIe errors (AER) in the log | Which port reported them | All from the Wi-Fi card's port, not the GPU's |

Some boots logged "No NVIDIA GPU found"; those were days the card had been
taken out of the machine on purpose.

### What the card does at idle

When the card has nothing to do, the driver drops it to performance state P8
and slows its PCIe link from Gen 3 (8 GT/s) to Gen 1 (2.5 GT/s) to save power.
As soon as something uses the GPU, the link has to retrain back up to Gen 3,
which includes an equalization step that is the part most sensitive to a
marginal electrical connection.

| State | P-state | PCIe link | Power |
|---|---|---|---|
| Idle | P8 | Gen 1 | ~7 W |
| Awake | P2 | Gen 3 | ~32 W |

The working theory: one of those Gen 1 to Gen 3 transitions fails, the card
drops off the bus, and the driver logs Xid 79. That fits everything above:
it only happened at idle, and it did not depend on the kernel or driver. At
least two failures came seconds after something woke the card (Ollama probing
the GPU, a media process).

### The keepalive

The keepalive takes the transition away by never letting the card go idle. It
lives in its own repository,
[rtx-keepalive](https://github.com/franzejr/rtx-keepalive), with install
instructions. It is a systemd user service that runs a tiny NVENC encode, 320×240 at 5 frames a
second, thrown away as it is produced. That is enough to hold the card at P2
and Gen 3, with GPU and encoder load rounding to zero.

`~/.config/systemd/user/rtx-keepalive.service`:

```ini
[Unit]
Description=Keep an NVIDIA GPU out of idle (P2 / full PCIe speed) with a minimal NVENC encode

[Service]
ExecStart=/usr/bin/ffmpeg -hide_banner -loglevel error -re -f lavfi -i testsrc=size=320x240:rate=5 -c:v h264_nvenc -f null -
Restart=always
RestartSec=10
Nice=19

[Install]
WantedBy=default.target
```

```sh
systemctl --user enable --now rtx-keepalive    # start now and at every boot
systemctl --user disable --now rtx-keepalive   # stop for good
```

It starts at boot without a login when lingering is on for the user
(`loginctl enable-linger`). The cost is about 25 W more while the machine is
on: roughly 18 kWh a month running 24 hours a day.

Started on 20 November 2026 at 19:48, it ran 13 hours and more without an
Xid, longer than any gap since the failures began. That supports the theory
but does not prove it yet: before the problem started, the card once went two
days without failing, so it needs several more days.

### What comes next

The keepalive hides the symptom. The cause is still physical, a link on the
edge: the second slot, the card itself, or its power.

1. **Leave the keepalive on for a few more days.** If the card falls off the
   bus with it running, the theory is wrong and the problem is the hardware
   alone.
2. **If it holds, cap the link speed in the BIOS** instead of paying for the
   keepalive. "Max Link Speed" (under M.I.T. › Miscellaneous Settings on
   Gigabyte Z370 boards) set to Gen 2 makes the jump smaller and skips Gen 3
   equalization; Gen 1 removes the speed changes entirely. Then stop the
   keepalive and watch Nvmon's chart and badge. Setting it to Gen 3 does not
   help: it is a ceiling, not a floor.
3. **To find the culprit**, move the card to the top PCIEX16 slot. If it stops
   failing there without the keepalive, the second slot was the problem.
4. **If it fails even with the keepalive**, try another PCIe power cable or
   PSU output and test the card in another machine.

If it fails again, run `sudo nvidia-bug-report.sh` before rebooting if the
system still answers, and save the kernel log afterwards with
`journalctl -b -1 -k --no-pager > kernel-failure.log`.

### Sources

- [NVIDIA Xid catalog](https://docs.nvidia.com/deploy/xid-errors/analyzing-xid-catalog.html)
- [XID 79, GPU has fallen off the bus: happens on idle, only](https://forums.developer.nvidia.com/t/xid-79-gpu-has-fallen-off-the-bus-happens-on-idle-only/323332)
- [Xid 79 while idling if ASPM L0s is enabled in UEFI BIOS](https://forums.developer.nvidia.com/t/nvidia-driver-xid-79-gpu-crash-while-idling-if-aspm-l0s-is-enabled-in-uefi-bios-gpu-has-fallen-off-the-bus/314453)
- [Nvidia graphics cards on Linux: PCIe link speed and width](https://billauer.se/blog/?p=5502)

## Shortcuts

| Key   | Action                                     |
|-------|--------------------------------------------|
| Space | Start the keepalive, or ask to stop it     |
| Enter | Confirm stopping the keepalive             |
| Esc   | Cancel, or close the shortcuts             |
| R     | Refresh now                                |
| ?     | Show or hide the shortcuts                 |
| Q     | Quit                                       |

## Build

```sh
bin/build      # build/nvmon
bin/test       # Qt Test, offscreen
bin/install    # makepkg -fsi, adds Nvmon to the app launcher
```

Needs `qt6-base`, `qt6-declarative`, `qt6-wayland`, and `nvidia-utils`, all
part of Omarchy on an NVIDIA machine.

The window follows the Omarchy theme and language. A Portuguese translation
is included; it shows when Omarchy's language is set to Portuguese.

## License

MIT. The theme and translator classes follow Omacut and Monologue by David
Heinemeier Hansson.
