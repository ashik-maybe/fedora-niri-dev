# niri-dev

A developer-focused Fedora respin: stock niri, stock noctalia, and a working
toolchain out of the box.

No themes. No dotfiles. No custom `niri/config.kdl`. If upstream niri or
noctalia changes something, this image inherits the change instead of fighting
it.

---

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

## Supported hardware

| GPU | Shipped in the ISO | After install |
| --- | --- | --- |
| **Intel** | Mesa, `libva-intel-media-driver`, `libva-intel-driver` | Pick the VA-API driver with `vainfo` (see below) |
| **AMD** | Mesa, `mesa-va-drivers-freeworld` | Nothing — hardware decode works out of the box |
| **NVIDIA** | Mesa + `nvidia-gpu-firmware` | `sudo dnf install akmod-nvidia` (see [NVIDIA](#nvidia)) |

Both laptop and desktop are first-class. Working suspend, brightness control and
power profiles are in the base image; desktop-only extras (`ddcutil` for
external monitor brightness) are included too.

## What's included

**Session**

`niri` `noctalia` `sddm` `sddm-wayland-generic` `xwayland-satellite`
`xdg-desktop-portal` `xdg-desktop-portal-gtk` `xdg-desktop-portal-gnome`
`gnome-keyring` `libsecret` `polkit` `qt6-qtwayland` `libappindicator-gtk3`
`xdg-user-dirs`

No separate polkit agent is shipped: noctalia implements one itself, so
`polkit-gnome` (retired in Fedora 45) is not needed. `libappindicator-gtk3` is
what lets `nm-applet` and `blueman-applet` appear in noctalia's system tray
instead of an XEmbed tray that a Wayland session does not have.

**Audio, network, bluetooth**

`pipewire` `pipewire-pulseaudio` `pipewire-alsa` `pipewire-utils` `wireplumber`
`alsa-ucm` `alsa-utils` `NetworkManager-wifi` `network-manager-applet` `bluez`
`blueman` `upower` `ddcutil`

`alsa-ucm` is not legacy cruft: PipeWire reads the same use-case profiles to pick
speaker and microphone routing on laptops, and the firmware packages below supply
the matching DSP blobs.

**Firmware and hardware**

`alsa-sof-firmware` `intel-audio-firmware` `cirrus-audio-firmware`
`amd-gpu-firmware` `intel-gpu-firmware` `nvidia-gpu-firmware` `atheros-firmware`
`brcmfmac-firmware` `iwlwifi-dvm-firmware` `iwlwifi-mvm-firmware`
`realtek-firmware` `mt7xxx-firmware` `amd-ucode-firmware` `microcode_ctl`
`fwupd` `gnome-firmware`

Fedora's `@hardware-support` group is not used: it also drags in `intel-lpmd`,
a daemon aimed at recent Intel laptops. The split above is the same payload with
no platform assumption, so the image boots on Intel, AMD and NVIDIA hardware,
laptop or desktop.

**Power and sensors**

`power-profiles-daemon` `thermald` `powertop` `lm_sensors` `brightnessctl`

**Graphics**

`mesa-dri-drivers` `mesa-vulkan-drivers` `vulkan-tools` `libva-utils`
`radeontop`

**Codecs (RPM Fusion)**

`libva-intel-media-driver` `libva-intel-driver` `mesa-va-drivers-freeworld`
`gstreamer1-plugins-good` `gstreamer1-plugins-bad-free`
`gstreamer1-plugins-bad-freeworld` `gstreamer1-plugins-ugly`
`gstreamer1-plugins-ugly-free` `gstreamer1-plugin-libav`
`gstreamer1-plugin-openh264` `gstreamer1-plugin-dav1d`
`libheif-freeworld` `unrar`

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

Full `ffmpeg` is preinstalled. RPM Fusion's `ffmpeg` conflicts with Fedora's
`ffmpeg-free`, and a kickstart `%packages` section cannot express
`--allowerasing`, so the swap runs in `%post`:

```bash
dnf swap -y ffmpeg-free ffmpeg --allowerasing
```

That buys libx264/libx265 and the rest of the encoders. Both RPM Fusion
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

**Terminal and shell**

`ptyxis` `nushell` `tmux` `bash`

**Fonts**

`default-fonts-core` — Fedora's own font metapackage, so future default font
changes arrive automatically.

**System health**

`snapper` `btrfs-assistant` `dnf5-plugin-automatic` `zram-generator`

**Browser and containers**

`google-chrome-stable` · `flatpak` (Flathub enabled, Flatseal preinstalled) ·
`podman` `podman-compose`

**Developer toolchain**

`git` `gh` `just` `gitui` `helix` `ripgrep` `fd-find` `bat` `eza` `fzf`
`zoxide` `direnv` `jq` `yq` `python3` `python3-pip` `python3-devel` `nodejs24`
`gcc` `make` `pkgconf`

`gitui` fills the TUI-git slot because `lazygit` was retired from Fedora and
this image does not add COPRs.

## Install

**Requirements:** x86_64 machine, wired or wireless network during install, a
USB stick of at least 2 GB.

1. Write the ISO to USB:
   ```bash
   sudo dd if=out/niri-dev-45-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
2. Boot it. The Fedora graphical installer starts with the kickstart already
   applied.
3. **Language / keyboard** — as usual.
4. **Installation source** — already configured; needs network access.
5. **Software selection** — pre-filled and locked. This is the spin.
6. **Installation destination** — your disk, your partitioning, your choice of
   encryption. Nothing is preselected.
7. **User creation** — your name and password.
8. **Begin installation**.

The kickstart deliberately omits partitioning and user creation. If it
specified them, Anaconda would install non-interactively and you would never
see the GUI. Leaving them out is what keeps the installer interactive.

## First boot

Three things worth checking once:

```bash
# 1. Hardware video decode is alive
vainfo | grep -E 'H264|HEVC|VP9'

# 2. If Intel and the list above is short, try the other driver
LIBVA_DRIVER_NAME=i965 vainfo

# 3. Chrome memory saver (8 GB machines especially)
#    chrome://settings/performance -> Memory Saver -> on
```

## Graphics and codecs

Fedora's own `ffmpeg-free` and `mesa-va-drivers` intentionally omit some
patent-encumbered components. This image enables RPM Fusion at install time and
swaps in the full `ffmpeg`, so both decode and encode work without a second trip
to the terminal.

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

Proprietary drivers are **not** in the ISO, because `akmod-nvidia` builds a
kernel module locally and Secure Boot systems require a MOK enrolment prompt at
the machine's own console. That is a decision for the user, not for an
unattended install.

```bash
sudo dnf install akmod-nvidia        # Turing and older
# or, for Turing and newer:
sudo dnf install akmod-nvidia-open
```

On Secure Boot systems the first boot will prompt you to enrol a MOK key —
complete it, or the module will not load.

NVIDIA hardware decode through VA-API needs `nvidia-vaapi-driver`, which is not
packaged for Fedora 45 in RPM Fusion. Chromium's own Vulkan-based decode path is
the practical option there.

## Per-machine notes

- [HP EliteBook 840 G3 / Skylake](for-elitebook-840-g3.md) — VA-API driver
  selection, AV1 avoidance, sleep mode, zram sizing, i915 quirks.

If a machine needs tweaks, add a file in that format rather than changing the
image. Hardware workarounds do not belong in a general-purpose spin.

## Building

```bash
just deps        # lorax, xorriso, isomd5sum
just fetch-base  # download the Fedora Everything netinst ISO
just build       # produce out/niri-dev-<release>-x86_64.iso
just check       # validate the kickstart
```

Build a different release:

```bash
FEDORA_RELEASE=46 just fetch-base build
```

The base is the **Fedora Everything netinst**, not a live ISO. That choice buys
three things: no privileged build container, an ISO small enough for a GitHub
release, and packages that resolve from live repos at install time — so an ISO
built in January installs June's packages.

`$releasever` and `$basearch` flow through the kickstart repo definitions, so a
release bump is a single variable change.

### Requirements

`niri` is in Fedora 43 and later; `noctalia` is in Fedora 44 and later. The
kickstart therefore targets **Fedora 44+**.

## Project layout

```
kickstart/niri-dev.ks      The spin definition. Everything else supports it.
files/noctalia.service     The one non-upstream artifact: session autostart.
files/zram-generator.conf  Swap-on-RAM sizing for developer workloads.
files/99-zram-sysctl.conf  swappiness/page-cluster tuning to match zram.
repos/google-chrome.repo   Shipped to /etc/yum.repos.d for Chrome updates.
justfile                   Local build entry points.
.github/workflows/         CI kickstart validation and ISO build.
```

## License

MIT. See [LICENSE](LICENSE).
