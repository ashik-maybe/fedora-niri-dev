# niri-dev

A developer-focused Fedora 45 respin built around [niri] — a scrollable
Wayland compositor — and [noctalia], its session shell. Stock niri and stock
noctalia, with the developer toolchain installed.

No themes. No dotfiles. The image ships one generated system config: it copies
niri's packaged default and changes only the program names for terminal,
launcher and lock, so upstream keymap changes still arrive. A user config at
`~/.config/niri/config.kdl` still overrides it.

The one deliberate exception to "Fedora's defaults" is swap sizing: the image
ships a `zram-generator.conf` and a matching `sysctl.d` file tuned for
developer workloads, documented in [Per-machine notes](#per-machine-notes).
Everything else — sleep, FBC/PSR, power profiles, VA-API driver selection — is
exactly as Fedora ships it.

The base is the **Fedora Everything netinst**, built with `mkksiso` and a
kickstart. Two ISOs come out: an online one that resolves packages at install
time, and an offline one that embeds the whole resolved package tree.

[niri]: https://github.com/YaLTeR/niri
[noctalia]: https://github.com/nickglynne/noctalia

---

## Contents

1. [Philosophy](#philosophy)
2. [What is in the image](#what-is-in-the-image)
3. [Hardware support](#hardware-support)
4. [AppImage support](#appimage-support)
5. [Install](#install)
6. [First boot](#first-boot)
7. [Graphics and codecs](#graphics-and-codecs)
8. [Per-machine notes](#per-machine-notes)
9. [Building](#building)
10. [What an offline build actually does](#what-an-offline-build-actually-does)
11. [Project layout](#project-layout)
12. [Troubleshooting](#troubleshooting)
13. [License](#license)

## Philosophy

A Fedora spin is a package selection plus the glue that makes a desktop
complete — not a redesign of the desktop. Fedora's GNOME spin doesn't patch
GNOME's defaults, and this image doesn't patch niri's or noctalia's.

That gives three rules:

1. **Ship the glue.** Greeter, portals, keyring, polkit agent, audio, network,
   power management, session autostart.
2. **Ship Fedora's defaults.** Fonts come from `default-fonts-core`, not a
   hand-picked font list. Branding stays Fedora's.
3. **Ship no opinions.** No colour schemes, no icon themes, no cursor packs, no
   shell config. The user customises after install.

The only non-upstream artifact in the image is one systemd user unit, because
niri deliberately does not autostart anything and noctalia has to be told to
run.

## What is in the image

**Session**

`niri` `noctalia` `sddm` `sddm-wayland-generic` `xwayland-satellite`
`xdg-desktop-portal` `xdg-desktop-portal-gtk` `xdg-desktop-portal-gnome`
`gnome-keyring` `libsecret` `polkit` `qt6-qtwayland` `libappindicator-gtk3`
`xdg-user-dirs`

No separate polkit agent is shipped: noctalia implements one itself, so
`polkit-gnome` (retired in Fedora 45) is not needed. `libappindicator-gtk3` is
what lets `nm-applet` and `blueman-applet` appear in noctalia's system tray
instead of an XEmbed tray that a Wayland session does not have.

`sddm-wayland-generic` pulls `weston`, so the login screen runs a second
compositor. The image keeps SDDM for a graphical login and accepts that cost.
`greetd` with `tuigreet` is the lean alternative for a text login.

**Audio, network, bluetooth**

`pipewire` `pipewire-pulseaudio` `pipewire-alsa` `pipewire-utils` `wireplumber`
`alsa-ucm` `alsa-utils` `NetworkManager-wifi` `network-manager-applet` `bluez`
`blueman` `upower` `ddcutil`

`alsa-ucm` is not legacy cruft: PipeWire reads the same use-case profiles to pick
speaker and microphone routing on laptops, and the firmware packages below supply
the matching DSP blobs.

**Firmware and hardware**

Every firmware package Fedora ships is installed, so the image does not assume
which hardware it lands on:

```
alsa-sof-firmware      intel-audio-firmware   cirrus-audio-firmware
amd-gpu-firmware       amd-ucode-firmware     intel-gpu-firmware
nvidia-gpu-firmware    atheros-firmware       brcmfmac-firmware
realtek-firmware       mt7xxx-firmware        nxpwireless-firmware
qcom-wwan-firmware     tiwilink-firmware      libertas-firmware
iwlegacy-firmware      iwlwifi-dvm-firmware   iwlwifi-mvm-firmware
iwlbluetooth-firmware  linux-firmware         wireless-regdb
fwupd
```

Fedora's `@hardware-support` group is not used: it also drags in `intel-lpmd`,
a daemon aimed at recent Intel laptops. The split above is the same payload with
no platform assumption, so the image boots on Intel, AMD and NVIDIA hardware,
laptop or desktop.

`kernel-modules-extra` is installed too: the long tail of sensors, old radios,
niche card readers and other devices the main module set does not carry, at
~3 MB.

**NVIDIA driver**

`akmod-nvidia` from RPM Fusion is preinstalled, together with everything it
needs to build at install time: `kernel-devel` (pinned to the kernel version the
tree contains), `gcc`, `make`, `kernel-headers`, `glibc-devel`. An offline ISO
has no second dnf pass, so a missing build dep would fail the install loudly
instead of shipping a broken driver. On Secure Boot systems the first boot will
prompt you to enrol a MOK key — complete it, or the module will not load.

**Power and sensors**

`power-profiles-daemon` `thermald` `powertop` `lm_sensors` `brightnessctl`

`thermald` is Intel-only and does nothing on AMD; it is kept because the
image is universal.

**Graphics**

`mesa-dri-drivers` `mesa-vulkan-drivers` `vulkan-tools` `libva-utils`
`radeontop`

**Codecs (RPM Fusion)**

`libva-intel-media-driver` `libva-intel-driver` `mesa-va-drivers-freeworld`
`gstreamer1-plugins-good` `gstreamer1-plugins-bad-free`
`gstreamer1-plugins-bad-freeworld` `gstreamer1-plugins-ugly`
`gstreamer1-plugins-ugly-free` `gstreamer1-plugin-libav`
`gstreamer1-plugin-openh264` `gstreamer1-plugin-dav1d`
`libheif-freeworld` `unrar` `ffmpeg`

GStreamer is listed explicitly because Chrome's WebRTC stack, screen recording
and Nautilus video thumbnails all go through it. The plugin split is deliberate:

- `gstreamer1-plugins-ugly` (RPM Fusion) is the H.264 **encoder** plugin
- `gstreamer1-plugins-ugly-free` (Fedora) is the 16 **decoder** plugins —
  a52, mpeg2, dvdread, dvdlpcm, wma — that the encoder package does not ship
- the `-freeworld` packages are additive on Fedora 45, not replacements:
  verified with `repoquery`, they declare no `Conflicts` and share no plugin
  files with their `-free` counterparts

The GStreamer VA-API plugin needs no package of its own: `libgstva.so` ships
inside `gstreamer1-plugins-bad-free`.

Full `ffmpeg` is preinstalled as an ordinary package. RPM Fusion's `ffmpeg-libs`
provides `libavcodec`/`libavformat`, so Fedora's `ffmpeg-free` is never selected
and the whole set resolves in one pass — no `--allowerasing` swap, and no
post-install transaction that needs a repository. That buys libx264/libx265 and
the rest of the encoders. Both RPM Fusion
repositories — `free` and `nonfree` — are enabled on the installed system,
and `unrar` is the one nonfree package shipped by default.

`libdvdcss` is **not available** for Fedora 45 in RPM Fusion, so encrypted DVD
playback is impossible. Unencrypted DVD media still decodes through
`dvdread`/`dvdnav` in `ugly-free`.

**Media**

`vlc` `yt-dlp` `playerctl` `cava` `wlsunset` `wf-recorder`

VLC is Fedora's own build as of Fedora 45; RPM Fusion supplies
`vlc-plugins-freeworld` on top, which is where DVD, Blu-ray and the remaining
formats come from.

**Files and documents**

`nautilus` `file-roller` `loupe` `papers` `gnome-text-editor`
`gnome-disk-utility` `seahorse` `gnome-font-viewer` `evolution-data-server`

**Screenshots and capture**

`grim` `slurp` `swappy` `wl-clipboard` `wl-mirror`

**AppImage support**

`fuse` `fuse-libs` — FUSE 2. A classic-runtime AppImage `dlopen`s
`libfuse.so.2` and execs `fusermount`; Fedora ships neither, so it fails with
`dlopen(): error loading libfuse.so.2`, which looks like a corrupt download.
Newer runtimes use libfuse3 (already present) or bundle FUSE statically, so
this covers the ones that would otherwise break.

Two packages, not one, and that is not obvious: `fuse` requires `fuse-common`
but **not** `fuse-libs`, so installing `fuse` alone gives you the helper and no
library. Neither conflicts with `fuse3`.

If a machine has no `/dev/fuse` at all (some containers, some kernels), the
runtime's own escape hatch still works: `./whatever.AppImage
--appimage-extract-and-run`.

**Terminal and shell**

`ptyxis` `nushell` `tmux` `bash`

**Fonts**

`default-fonts-core` — Fedora's own font metapackage, so future default font
changes arrive automatically.

**System health**

`snapper` `btrfs-assistant` `dnf5-plugin-automatic` `zram-generator`

**Browser and containers**

`google-chrome-stable` · `flatpak` (Flathub enabled, Flatseal and Gear Lever
preinstalled) · `podman` `podman-compose`

**Developer toolchain**

`git` `gh` `just` `gitui` `helix` `ripgrep` `fd-find` `bat` `eza` `fzf`
`zoxide` `direnv` `jq` `yq` `python3` `python3-pip` `python3-devel` `nodejs24`
`gcc` `make` `pkgconf`

`gitui` fills the TUI-git slot because `lazygit` was retired from Fedora and
this image does not add COPRs.

## Hardware support

| GPU | Shipped in the ISO | After install |
| --- | --- | --- |
| **Intel** | Mesa, `libva-intel-media-driver`, `libva-intel-driver` | Pick the VA-API driver with `vainfo` (see below) |
| **AMD** | Mesa, `mesa-va-drivers-freeworld` | Nothing — hardware decode works out of the box |
| **NVIDIA** | Mesa + `nvidia-gpu-firmware` + `akmod-nvidia` | Enrol the MOK key at first boot if Secure Boot is on |

Both laptop and desktop are first-class. Working suspend, brightness control and
power profiles are in the base image; desktop-only extras (`ddcutil` for
external monitor brightness) are included too.

The image was scanned against an **HP EliteBook 840 G3** (Skylake i5-6300U,
Intel HD 520, Intel 8260 Wi-Fi/Bluetooth, Intel HDA audio) to prove nothing is
missing:

| Component | Driver / module | Ships in | Blob it loads |
| --- | --- | --- | --- |
| HD Graphics 520 | `i915` | `kernel-modules` | `i915/skl_dmc_ver1_27.bin` — `intel-gpu-firmware` |
| Wi-Fi 8260 (iwlmvm) | `iwlwifi`, `iwlmvm` | `kernel-modules` | `iwlwifi-8000C-36.ucode` — `iwlwifi-mvm-firmware` |
| Bluetooth 8087:0a2b | `btusb` | `kernel-modules` | `intel/ibt-11-5.sfi`, `.ddc` — `iwlbluetooth-firmware` |
| Audio (HDA, CX20724) | `snd_hda_intel`, `snd_hda_codec_conexant` | `kernel-modules` | none — legacy HDA uses the kernel mixer, not UCM |
| Ethernet I219-LM | `e1000e` | `kernel-modules-core` | — |
| Card reader RTS522A | `rtsx_pci` | `kernel-modules-core` | — |
| Webcam (Chicony) | `uvcvideo` | `kernel-modules` | — |
| Touchpad (Synaptics PS/2) | `psmouse` | built into the kernel | — |
| Accelerometer LIS3LV02DL | `hp_accel`, `hp_wmi` | `kernel-modules` | — |
| Thermal, RAPL, MEI | `intel_pch_thermal`, `coretemp`, `intel_rapl_msr`, `mei_me` | `kernel-modules-core` | — |
| CPU microcode | — | `microcode_ctl` | `intel-ucode/06-4e-03` (Skylake-U) |

Ownership was verified against which Fedora package ships each blob (not
against a host that happens to have everything installed), and the driver
side against the running system: every PCI device on the board has a driver bound, and the kernel log
records no failed firmware load. Two things the scan settled:

- **Audio is legacy HDA on the 840 G3, not SOF.** `snd_intel_dspcfg` sits at
  `dsp_driver=0` (auto), the board exposes no SOF ACPI node, and
  `snd_hda_intel` binds the CX20724 codec with HP's own `103c:8079` fixup.
  `alsa-sof-firmware` is installed anyway — it costs 14 MB and the image is
  hardware-agnostic.
- **`kernel-modules-extra` is not needed for this laptop.** Every module above
  lives in `kernel-modules` or `kernel-modules-core`, both of which come with
  `kernel`. It is installed for other hardware.

`kernel` is listed explicitly, not implied. Anaconda adds a kernel by itself only
when it can resolve one from an enabled repository; when it cannot, it logs
`Failed to select a kernel` and carries on installing. An online install never
notices, because Fedora's repos have one. An offline install has only the
embedded tree, so the kernel is in the tree because the kickstart asked for it —
and `%post` gates on `kernel` being installed, so a regression fails the install
instead of shipping an ISO that cannot boot.

## AppImage support

`fuse` + `fuse-libs`. A classic-runtime AppImage `dlopen`s `libfuse.so.2` and
execs `fusermount`, and Fedora ships neither, so it fails with
`dlopen(): error loading libfuse.so.2` — which reads like a corrupt download.
Newer runtimes use libfuse3 (already present) or bundle FUSE statically, so this
covers the ones that would otherwise break. Two packages, not one: `fuse`
requires only `fuse-common`, so it brings the helper and not the library.

Gear Lever, the AppImage browser/integrator, is preinstalled as a Flatpak. It
talks to `org.freedesktop.Flatpak` so the AppImage runs on the host, not inside
the sandbox, which is why `fuse` is a package here and not a side effect of the
Flatpak.

## Install

Two ISOs come out of this repository. They install the same system; they differ
only in where the packages come from.

| ISO | Size | Install needs network | Built by |
| --- | --- | --- | --- |
| `…-45-x86_64.iso` | ~1.3 GB | yes | `./build.sh online` |
| `…-45-x86_64-offline.iso` | ~3.0 GB | **no** | `./build.sh offline` |

Both fit a 4 GB USB stick.

**Requirements:** x86_64 machine, a USB stick of at least 4 GB, and — for the
online ISO only — wired or wireless network during install.

1. Write the ISO to USB:
   ```bash
   sudo dd if=out/niri-dev-45-x86_64-offline.iso of=/dev/sdX \
     bs=4M status=progress oflag=sync
   ```
2. Boot it. The Fedora graphical installer starts with the kickstart already
   applied.
3. **Language / keyboard** — as usual.
4. **Installation source** — already configured. The offline ISO points at a
   package repository embedded in the ISO itself.
5. **Software selection** — pre-filled and locked. This is the spin.
6. **Installation destination** — your disk, your partitioning, your choice of
   encryption. Nothing is preselected.
7. **User creation** — your name and password.
8. **Begin installation**.

The kickstart deliberately omits partitioning and user creation. If it
specified them, Anaconda would install non-interactively and you would never
see the GUI. Leaving them out is what keeps the installer interactive.

### What "offline" does and does not cover

The offline ISO embeds the resolved RPM closure (~2 GB) as a `createrepo_c`
repository, and the generated kickstart installs from
`file:///run/install/repo/packages`. No mirror is contacted at any point: the
RPM Fusion release packages and the Chrome signing key are shipped on the ISO
too, so `%post` does not download anything either.

One thing still needs a network, and the build says so out loud: **Flatseal** and
**Gear Lever** are Flatpaks, so they are skipped during an offline install with a
warning. Add the Flathub remote and install them after first boot. Updates also
need a network, so right after an offline install your system is the package set
that was current when the ISO was built.

## First boot

Four things worth checking once:

```bash
# 1. Hardware video decode is alive
vainfo | grep -E 'H264|HEVC|VP9'

# 2. If Intel and the list above is short, try the other driver
LIBVA_DRIVER_NAME=i965 vainfo

# 3. AppImage support: both lines must print something
ldconfig -p | grep libfuse.so.2 && command -v fusermount

# 4. Chrome memory saver (8 GB machines especially)
#    chrome://settings/performance -> Memory Saver -> on
```

On NVIDIA hardware, also check the module built:

```bash
nvidia-smi            # after the MOK enrolment prompt at first boot
journalctl -b | grep akmod
```

## Graphics and codecs

Fedora's own `ffmpeg-free` and `mesa-va-drivers` intentionally omit some
patent-encumbered components. This image installs RPM Fusion's full `ffmpeg` as
an ordinary package, so both decode and encode work without a second trip to the
terminal. `ffmpeg-free` is never selected: RPM Fusion's `ffmpeg-libs` satisfies
every `libavcodec`/`libavformat` requirement in the transaction.

### Intel

Both VA-API backends ship:

```bash
LIBVA_DRIVER_NAME=iHD  vainfo   # from libva-intel-media-driver, modern
LIBVA_DRIVER_NAME=i965 vainfo   # from libva-intel-driver, legacy
```

Keep whichever lists more profiles. On Gen9 (Skylake/Kaby Lake) the two differ
noticeably; on Gen12+ only `iHD` matters.

### AMD

Nothing to do. `mesa-va-drivers-freeworld` covers H.264/HEVC decode on
radeonsi, and `radeontop` is there if you want to watch the GPU.

### NVIDIA

`akmod-nvidia` is preinstalled and builds at install time. On Secure Boot
systems the first boot will prompt you to enrol a MOK key — complete it, or the
module will not load.

NVIDIA hardware decode through VA-API needs `nvidia-vaapi-driver`, which is not
packaged for Fedora 45 in RPM Fusion. Chromium's own Vulkan-based decode path is
the practical option there.

## Per-machine notes

- [HP EliteBook 840 G3 / Skylake](for-elitebook-840-g3.md) — VA-API driver
  selection, AV1 avoidance, sleep mode, i915 quirks.

If a machine needs tweaks, add a file in that format rather than changing the
image. Hardware workarounds do not belong in a general-purpose spin.

## Building

Everything goes through `build.sh`; `just` is a thin wrapper around it, and the
GitHub workflow only validates the kickstart.

```bash
./build.sh deps       # lorax, pykickstart, xorriso, isomd5sum, podman
./build.sh base       # netinst ISO + RPM Fusion release RPMs + key + comps
./build.sh online     # out/niri-dev-45-x86_64.iso          (~1.3 GB)
./build.sh offline    # out/niri-dev-45-x86_64-offline.iso  (~3.0 GB)
./build.sh packages   # just resolve the package tree (packages/, ~2 GB)
./build.sh check      # kickstart validation + bash -n on every %pre/%post
./build.sh preflight  # disk, tools, mirrors, container: will this machine build?
./build.sh test-iso   # content + boot test of an out/*.iso (pass its path)
```

With `just`, the same steps are `just fetch-base`, `just build`,
`just build-offline`, `just packages`, `just check`, `just preflight`,
`just test-iso`.

### What a local build needs

- a Linux host — Fedora preferred, but any Linux with podman works, because the
  package resolution runs in a `fedora:$FEDORA_RELEASE` container
- ~14 GB of free disk for the offline ISO (~900 MB netinst, ~2 GB package tree,
  ~3 GB output, plus scratch)
- network access on the first build
- `sudo`, for `./build.sh deps` and the single `mkksiso` step

`out/`, `packages/`, `cache/` and `build/` are git-ignored; a clone builds as
is, and the offline tree re-resolves itself whenever the kickstart changes.

Build a different release:

```bash
FEDORA_RELEASE=46 ./build.sh base
FEDORA_RELEASE=46 ./build.sh offline
```

The base is the **Fedora Everything netinst**, not a live ISO. That choice keeps
the online ISO small and makes its packages resolve from live repositories at
install time — an ISO built in January installs June's packages. The offline ISO
is the opposite trade: it installs exactly what was resolved when it was built.

`$releasever` and `$basearch` flow through the kickstart repo definitions, so a
release bump is a single variable change. `./build.sh base` keeps an ISO it
already has; `REFRESH=1 ./build.sh base` looks for a newer point release.

`mkksiso` rebuilds the ISO's EFI boot image with `mkfs.vfat`, which needs a loop
device and therefore root. `build.sh` elevates **only that command** and gives
the resulting file back to you; downloads, the package tree and `out/` stay
owned by your user.

### What an offline build actually does

1. `cache/comps.xml` expands `@core`, `@standard` and the explicit package list
   into a flat list, using the same rules Anaconda uses.
2. `dnf install --installroot=<empty> --downloadonly` resolves that list against
   live Fedora, RPM Fusion and Chrome repositories and downloads the whole
   closure. An empty rpmdb is what makes the result an installed set rather than
   a delta against your machine.
3. `createrepo_c` indexes `packages/`, which is then added to the ISO root.
4. The kickstart is copied with two edits: the remote `repo` lines become the
   embedded repository, and `%packages` becomes the resolved list. Everything
   else, `%post` included, is shared with the online image.

The result is verified before packaging, twice: the package tree must resolve
against only `file://…/packages` with zero problems (no network reachable), and
the generated offline kickstart must pass the same kickstart validation the
source one does. On Fedora 45 that is 1428 packages.

The package resolution runs inside a
`registry.fedoraproject.org/fedora:$FEDORA_RELEASE` container, so an older
Fedora host can still build a correct image for the target release, and the
resolver's RPM Fusion release packages stay out of your system. Leave
`BUILD_IMAGE` unset on a normal host; `BUILD_IMAGE=none` is only for when you
are already inside a disposable container of the target release (it runs the
resolver against the running system).

### Requirements

`niri` is in Fedora 43 and later; `noctalia` is in Fedora 44 and later. The
kickstart therefore targets **Fedora 44+**.

## Project layout

```
kickstart/niri-dev.ks      The spin definition. Everything else supports it.
files/noctalia.service     Session autostart of noctalia.
files/niri-glue.sh         Builds /etc/niri/config.kdl from the packaged default.
files/zram-generator.conf  Swap-on-RAM sizing for developer workloads.
files/99-zram-sysctl.conf  swappiness/page-cluster tuning to match zram.
repos/google-chrome.repo   Shipped to /etc/yum.repos.d for Chrome updates.
build.sh                   All build entry points, online and offline.
scripts/check-kickstart.sh ksvalidator + bash -n on every %pre/%post.
scripts/expand-packages.py comps + %packages -> explicit package list.
scripts/resolve-packages.sh Downloads that list into packages/.
scripts/make-offline-ks.py Writes the offline ISO's kickstart.
scripts/preflight.sh    Environment readiness check, before the heavy steps.
scripts/test-iso.sh     Content + boot test of a built ISO.
justfile                   Thin wrappers around build.sh.
.github/workflows/         Kickstart validation on push and PR.
```

## Troubleshooting

- **"dlopen(): error loading libfuse.so.2"** — the AppImage is a classic-runtime
  build and `fuse-libs` is missing. It is in the image; if you see this on a
  different machine, install `fuse-libs`.
- **NVIDIA black screen** — `akmod-nvidia` builds at install time. If the build
  failed, the install still succeeded and you get nouveau. Rebuild with
  `sudo akmods --force` and check `journalctl -b | grep akmod`. On Secure Boot
  systems the MOK enrolment prompt at first boot is required; skipping it leaves
  the module unsigned and unloaded.
- **Boot after offline install, no kernel** — this was a real bug before
  `kernel` was listed explicitly. If you have an old ISO, the kickstart in this
  repository is the fix; rebuild.
- **No network after install** — check `ip link` and `nmcli device status`. The
  image carries every wireless firmware package, so a missing blob is not the
  usual cause; a regulatory-domain problem is. `sudo fwupdmgr refresh &&
  sudo fwupdmgr update` sometimes fixes a stale `wireless-regdb`.

## License

MIT. See [LICENSE](LICENSE).
