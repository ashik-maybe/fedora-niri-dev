# HP EliteBook 840 G3 — software notes

Software-only tuning for **Intel Core i5-6300U (Skylake) / HD Graphics 520 /
7.5 GiB usable RAM**.

This file intentionally says nothing about hardware upgrades. It is about
getting the most out of the machine as it is.

Every command here is safe to run as your normal user unless prefixed with
`sudo`.

---

## 1. What the platform means

Skylake is Gen9 graphics. Two consequences drive almost everything in this
document:

- **No AV1 hardware decode.** AV1 arrived with Gen12 (Tiger Lake). Every AV1
  stream is decoded on the CPU — on a 15 W dual-core that is the difference
  between a cool lap and a hot one.
- **No `xe` driver, ever.** This is an `i915` machine permanently. Advice
  written for 12th gen and newer does not apply.

Also: **no `intel-lpmd`**. That daemon is for Lunar Lake and newer and is a
no-op here. It is intentionally absent from the image.

## 2. VA-API: pick the right driver

Two backends ship in the image. They are not equivalent on Gen9 — `iHD`'s
Skylake support is thinner than `i965`'s.

```bash
# modern driver
LIBVA_DRIVER_NAME=iHD  vainfo

# legacy driver
LIBVA_DRIVER_NAME=i965 vainfo
```

Expected profiles on this GPU:

| Profile | Available |
| --- | --- |
| `VAProfileH264High` | yes |
| `VAProfileHEVCMain` | yes (8-bit only) |
| `VAProfileVP9Profile0` | yes |
| `VAProfileVP9Profile2` | **no** — 10-bit VP9 is not supported |
| `VAProfileAV1Profile0` | **no** — never on this hardware |

Keep whichever driver reports the first three. Whichever you choose, pin it so
applications agree:

```bash
echo 'LIBVA_DRIVER_NAME=i965' >> ~/.config/environment.d/vaapi.conf
```

To make it system-wide instead, put it in `/etc/environment.d/90-vaapi.conf`.
Verify after a re-login with a plain `vainfo`.

Check that all three profiles are present after install and after any Mesa or
kernel update. The installer only *warns* if `vainfo` reports nothing, because
VMs and NVIDIA machines legitimately have no VA-API device — on this hardware
the profiles should always be there:

```bash
vainfo | grep -q VAProfileH264High    || echo "H.264 decode missing"
vainfo | grep -q VAProfileHEVCMain    || echo "HEVC decode missing"
vainfo | grep -q VAProfileVP9Profile0 || echo "VP9 decode missing"
```

## 3. The AV1 trap

YouTube prefers AV1 whenever the client advertises support. Chrome does. HD 520
does not. So YouTube quietly falls back to CPU decoding and your fan spins up.

Two fixes:

**Browser:** install `enhanced-h264ify` (Chromium extension). It makes YouTube
serve H.264, which the GPU decodes in hardware for free.

**Downloads:** always exclude AV1 in `yt-dlp`:

```bash
yt-dlp -f "bv[vcodec!*=av01]+ba/b"
```

Put that in `~/.config/yt-dlp/config` and forget about it.

This single item will do more for battery life and fan noise than any kernel
parameter below.

## 4. Sleep instead of s2idle

Skylake-era HP firmware implements `deep` (S3) far better than `s2idle`.
`s2idle` on this generation tends to wake with a warm chassis and a flat
battery.

```bash
cat /sys/power/mem_sleep          # look for [deep] vs [s2idle]
```

If `deep` is available but not the default:

```bash
sudo grubby --update-kernel=ALL --args="mem_sleep_default=deep"
```

Reboot, then confirm the brackets moved:

```bash
cat /sys/power/mem_sleep
```

Trade-off: resume takes a second or two longer. Worth it.

## 5. i915 power knobs

**Framebuffer compression** saves power on idle desktops:

```bash
sudo grubby --update-kernel=ALL --args="i915.enable_fbc=1"
```

**Panel self-refresh** can cause flicker or the occasional stuck frame on some
840 G3 panels. If you see either, disable it — don't live with flicker:

```bash
sudo grubby --update-kernel=ALL --args="i915.enable_psr=0"
```

Apply one change at a time so you know which one did what. Check current
effective values with:

```bash
sudo dmesg | grep -iE 'fbc|psr'
```

## 6. zram sizing for 7.5 GiB

The image ships this at `/etc/systemd/zram-generator.conf`:

```ini
[zram0]
zram-size = ram * 0.75
compression-algorithm = zstd
```

Why not Fedora's default (`min(ram/2, 4096)`)? Because swap-on-RAM is cheap:
with zstd at roughly 3:1, a 6 GB zram device costs about 2 GB of actual RAM and
absorbs the Chrome-tab cliff that 8 GB machines hit. Swap to disk costs nothing
but time; swap to zram costs a little RAM and no time.

Matching sysctl (`/etc/sysctl.d/99-zram.conf`):

```ini
vm.swappiness = 100
vm.page-cluster = 0
```

The default `swappiness=60` is tuned for spinning disks. When the swap device is
compressed RAM, swapping earlier is correct. `page-cluster=0` stops readahead
from pulling 128 KB when a single 4 KB page is wanted from zram.

Apply without a reboot:

```bash
sudo sysctl --system
systemctl daemon-reload && systemctl restart systemd-zram-setup@zram0.service
zramctl
```

## 7. Memory hygiene

7.5 GiB is the real limit on this machine, not the CPU.

- **Chrome Memory Saver on.** `chrome://settings/performance`. Non-negotiable
  here.
- **One language server at a time.** `pyright` is a Node process costing
  ~200 MB. Helix spawns what you configure; don't run `pyright` and
  `typescript-language-server` and `bash-language-server` for a Bash edit.
- **Watch what `systemd-oomd` kills** rather than guessing:
  ```bash
  journalctl -u systemd-oomd -b
  ```
- **Prefer resource-light editors for quick edits.** Helix is in the image for a
  reason; it starts in milliseconds and idles at a few tens of MB.

## 8. powertop — read, don't auto-tune

`powertop` is installed as a diagnostic:

```bash
sudo powertop --calibrate     # takes a few minutes, do it on battery
sudo powertop                 # Tab to "Tunables"
```

**Never run `sudo powertop --auto-tune` on this machine.** It routinely
disables the touchpad and knocks the Wi-Fi card's power states into a
configuration it does not recover from cleanly. Read the tunables list and apply
individual changes by hand, one at a time, testing after each.

The genuinely safe ones are usually the USB autosuspend entries and the
`/sys/bus/pci/.../power/control` writes. Leave everything else alone.

## 9. TPM — check before you plan around it

`systemd-cryptenroll --tpm2-device=auto` is a great quality-of-life win, but
only if the machine actually has TPM 2.0. Many 840 G3 units shipped TPM 1.2.

```bash
cat /sys/class/tpm/tpm0/tpm_version_major
```

- `2` → TPM2 LUKS auto-unlock will work:
  ```bash
  sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p3
  ```
- `1` → that path is closed on this unit. A passphrase per boot is the
  realistic option.

## 10. Fingerprint reader

Whether `fprintd` works here depends entirely on which sensor your unit shipped
with:

```bash
lsusb | grep -iE '138a|06cb|validity|synaptics'
```

If nothing matches, there is no reader and this section is done.

If something matches, test before touching PAM:

```bash
fprintd-enroll
fprintd-verify
```

Only after `verify` succeeds should you wire it into login:

```bash
sudo authselect enable-feature with-fingerprint
```

That covers SDDM and `sudo`. If enrolment fails, stop — a half-configured PAM
stack is worse than no fingerprint at all.

## 11. Wi-Fi contingency

```bash
lspci -nn | grep -i network
```

- **Intel** (`8086:...`) — `iwlwifi`, nothing to do.
- **Broadcom** — needs `broadcom-wl` from RPM Fusion:
  ```bash
  sudo dnf install akmod-wl
  ```
  Be aware this module is rebuilt on every kernel update and is the most
  fragile part of the system when present. If the machine is on Broadcom and
  Wi-Fi breaks after an update, this is why.

## 12. Noctalia autostart fallback

Noctalia runs as a systemd user unit (`noctalia.service`), enabled for
`graphical-session.target`. This is the most likely thing to misbehave, because
niri deliberately starts nothing on its own.

If you log in and get a bare niri with no bar:

```bash
systemctl --user status noctalia.service
journalctl --user -u noctalia.service -b
```

If it never starts, the documented upstream fallback is one line in
`~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "noctalia"
```

That works because niri passes its environment to children it spawns, which is
exactly what a systemd user unit relies on.

## 13. Verification checklist

Run after install and after any kernel or Mesa update:

```bash
# 1. Hardware decode present
vainfo | grep -E 'H264|HEVC|VP9'

# 2. Which driver won
echo "LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-unset}"

# 3. Sleep mode
cat /sys/power/mem_sleep

# 4. zram is live and sized sensibly
zramctl

# 5. Swappiness
sysctl vm.swappiness vm.page-cluster

# 6. Session unit healthy
systemctl --user is-active noctalia.service

# 7. Kernel args landed
cat /proc/cmdline | tr ' ' '\n' | grep -E 'mem_sleep|i915'
```

If 1 fails after an update, force the other driver and re-check. If 3 shows
`[s2idle]`, the `grubby` command from section 4 did not take.
