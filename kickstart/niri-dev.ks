#version=DEVEL
#
# niri-dev — a developer-focused Fedora respin
# ============================================
#
# Stock niri + stock noctalia + a working toolchain. See README.md for the
# philosophy and the full package rationale.
#
# IMPORTANT — interactive GUI install by design
# ---------------------------------------------
# Partitioning, rootpw and user creation are deliberately NOT specified here.
# A "complete" kickstart makes Anaconda install unattended without ever showing
# its interface. Omitting those three keeps the graphical installer on screen
# with language, repos and packages pre-filled, and lets the user choose their
# own disk layout and password.
#
# Add `autopart`, `rootpw` and `user` only if you want an unattended install.

# --- Locale and time ------------------------------------------------------
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone UTC --utc

# --- Installer behaviour --------------------------------------------------
# Graphical installer. Never `text` or `cmdline` here.
graphical
firstboot --disable

# --- Security -------------------------------------------------------------
selinux --enforcing
firewall --enabled --service=mdns

# --- Repositories ---------------------------------------------------------
# Fedora's own repositories are inherited from the netinst ISO.
# Third-party repositories needed to resolve packages below.
#
# $releasever and $basearch are substituted by Anaconda, so a Fedora release
# bump needs no edits here.

# Kickstart commands are line-based: no backslash continuations.
#
# No --gpgkey option exists for `repo`: Anaconda sets pkg_gpgcheck=False for
# installer repositories, so these entries are used unsigned at install time.
# The target system trusts RPM Fusion through its release packages and Google
# Chrome through an explicit `rpm --import` in %post.

repo --name="google-chrome" --baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64

repo --name="rpmfusion-free" --baseurl=https://download1.rpmfusion.org/free/fedora/releases/$releasever/Everything/$basearch/os/

repo --name="rpmfusion-free-updates" --baseurl=https://download1.rpmfusion.org/free/fedora/updates/$releasever/$basearch/

# RPM Fusion nonfree is enabled but ships nothing by default: the ISO stays
# generic, and the repo is there for what users add later (akmod-nvidia, unrar,
# media extras). Fedora 45 now provides libva-intel-media-driver itself, so the
# Intel VA-API backend no longer needs a nonfree package at install time.

repo --name="rpmfusion-nonfree" --baseurl=https://download1.rpmfusion.org/nonfree/fedora/releases/$releasever/Everything/$basearch/os/

repo --name="rpmfusion-nonfree-updates" --baseurl=https://download1.rpmfusion.org/nonfree/fedora/updates/$releasever/$basearch/

# --- Packages -------------------------------------------------------------
%packages --ignoremissing

@core
@standard

# Session
niri
noctalia
sddm
sddm-wayland-generic
xwayland-satellite
xdg-desktop-portal
xdg-desktop-portal-gtk
xdg-desktop-portal-gnome
gnome-keyring
libsecret
polkit
qt6-qtwayland
libappindicator-gtk3
xdg-user-dirs

# Audio, network, bluetooth
#
# alsa-ucm matters beyond ALSA: PipeWire reads the same use-case profiles to
# pick the right speaker/mic routing on laptops, and the firmware packages
# further down supply the matching DSP blobs.
pipewire
pipewire-pulseaudio
pipewire-alsa
pipewire-utils
wireplumber
alsa-ucm
alsa-utils
NetworkManager-wifi
network-manager-applet
bluez
blueman
upower
ddcutil

# Firmware and hardware enablement
#
# Fedora's @hardware-support comps group is not used: it also pulls
# intel-lpmd, a daemon that only makes sense on recent Intel laptops. The
# firmware split below is the same payload without any platform assumption, so
# the image boots on Intel/AMD/NVIDIA, laptop or desktop. Missing firmware is
# the usual reason a generic image feels wrong on some machine, so every
# vendor package here is intentional.
alsa-sof-firmware
intel-audio-firmware
cirrus-audio-firmware
amd-gpu-firmware
intel-gpu-firmware
nvidia-gpu-firmware
atheros-firmware
brcmfmac-firmware
iwlwifi-dvm-firmware
iwlwifi-mvm-firmware
realtek-firmware
mt7xxx-firmware
amd-ucode-firmware
microcode_ctl
fwupd
gnome-firmware

# Power and sensors
power-profiles-daemon
thermald
powertop
lm_sensors
brightnessctl

# Graphics
mesa-dri-drivers
mesa-vulkan-drivers
vulkan-tools
libva-utils
radeontop

# Codecs (RPM Fusion)
#
# Deliberately absent: ffmpeg and libavcodec-freeworld. RPM Fusion's ffmpeg
# conflicts with Fedora's ffmpeg-free, which VLC and the GStreamer plugins link
# against, and a %packages section cannot perform an --allowerasing swap. A
# conflicting request fails the whole install. Fedora's ffmpeg-free already
# decodes H.264 and HEVC; full encoder support is an optional post-install swap
# documented in README.md.
#
# Deliberately absent: mesa-vdpau-drivers-freeworld. It no longer exists as a
# separate package on Fedora 45; mesa-va-drivers-freeworld obsoletes it.
#
# GStreamer is listed explicitly because WebRTC in Chrome, screen recording and
# the Nautilus video thumbnails all go through it. libav is the decoder for
# H.264/HEVC without the full ffmpeg swap.
libva-intel-media-driver
libva-intel-driver
mesa-va-drivers-freeworld
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugins-bad-freeworld
gstreamer1-plugins-ugly
gstreamer1-plugin-libav
gstreamer1-plugin-openh264
gstreamer1-plugin-dav1d
libheif-freeworld

# Media
#
# vlc is Fedora's own build as of Fedora 45; RPM Fusion only adds
# vlc-plugins-freeworld on top, which is optional.
vlc
yt-dlp
playerctl
cava
wlsunset
wf-recorder

# Files and documents
nautilus
file-roller
loupe
papers
gnome-text-editor
gnome-disk-utility
seahorse
gnome-font-viewer
evolution-data-server

# Screenshots and capture
grim
slurp
swappy
wl-clipboard
wl-mirror

# Terminal and shell
ptyxis
nushell
tmux
bash

# Fonts — Fedora's own metapackage, not a hand-picked list
default-fonts-core

# System health
snapper
btrfs-assistant
dnf5-plugin-automatic
zram-generator

# Browser and containers
google-chrome-stable
flatpak
podman
podman-compose

# Developer toolchain
git
gh
just
gitui
helix
ripgrep
fd-find
bat
eza
fzf
zoxide
direnv
jq
yq
python3
python3-pip
python3-devel
nodejs24
gcc
make
pkgconf

%end

# --- Install files shipped on the ISO -------------------------------------
# Runs outside the chroot, so it only copies files. The ISO is mounted at
# /run/install/repo; the installed root is $ANA_INSTALL_PATH.

%post --nochroot --erroronfail --log=/root/ks-post-nochroot.log
set -euxo pipefail

root="${ANA_INSTALL_PATH:-/mnt/sysimage}"
src=/run/install/repo/files

install -Dm0644 "$src/noctalia.service"        "$root/usr/lib/systemd/user/noctalia.service"
install -Dm0644 "$src/zram-generator.conf"     "$root/etc/systemd/zram-generator.conf"
install -Dm0644 "$src/99-zram-sysctl.conf"     "$root/etc/sysctl.d/99-zram.conf"
install -Dm0644 /run/install/repo/repos/google-chrome.repo "$root/etc/yum.repos.d/google-chrome.repo"

# Enable the user unit statically: `systemctl --user enable` cannot run here,
# but a wants-symlink is exactly what it would create.
mkdir -p "$root/etc/systemd/user/graphical-session.target.wants"
ln -sfn /usr/lib/systemd/user/noctalia.service \
        "$root/etc/systemd/user/graphical-session.target.wants/noctalia.service"

%end

# --- System configuration -------------------------------------------------
# Runs inside the installed system, so systemctl/systemctl/rpm/dnf work.

%post --erroronfail --log=/root/ks-post.log
set -euxo pipefail

release="$(rpm -E %fedora)"

# 1. Persist the third-party repositories for the installed system.
#    The `repo` lines above only configure the installer, and Anaconda writes
#    them into /etc/yum.repos.d as a side effect. Drop those generated files
#    first: the release packages below ship the maintained, signed versions, and
#    leaving both would duplicate sections.
rm -f /etc/yum.repos.d/rpmfusion-free.repo \
      /etc/yum.repos.d/rpmfusion-free-updates.repo \
      /etc/yum.repos.d/rpmfusion-nonfree.repo \
      /etc/yum.repos.d/rpmfusion-nonfree-updates.repo

dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm"

# Chrome's repo file is shipped on the ISO, so trust its signing key up front
# instead of letting the first `dnf upgrade` stop for a key prompt.
rpm --import https://dl.google.com/linux/linux_signing_key.pub

# 2. Graphical boot by default, with SDDM as the greeter.
systemctl set-default graphical.target
systemctl enable sddm.service

# 3. Flathub, and the one Flatpak this image ships. Both steps need network and
#    a working /var inside the chroot; if either is flaky, warn and move on
#    rather than failing an otherwise good install.
flatpak remote-add --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo || \
  echo "WARNING: could not add the flathub remote" >&2
flatpak install -y --system flathub com.github.tchx84.Flatseal || \
  echo "WARNING: Flatseal not preinstalled; run 'flatpak install flathub com.github.tchx84.Flatseal' after first boot" >&2

# 4. Nushell as the login shell, keeping bash installed for scripts.
grep -qx /usr/bin/nu /etc/shells || echo /usr/bin/nu >> /etc/shells
while IFS=: read -r name _ uid _; do
  [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ] && usermod -s /usr/bin/nu "$name" || true
done < /etc/passwd

# 5. Chrome as the default browser. Written as a system-wide XDG default
#    because `xdg-settings` needs a live user session.
cat > /etc/xdg/mimeapps.list <<'EOF'
[Default Applications]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
x-scheme-handler/about=google-chrome.desktop
text/html=google-chrome.desktop
EOF

# 6. Security updates in the background. Units differ between dnf4 and dnf5,
#    so probe instead of assuming.
if [ -f /etc/dnf/automatic.conf ]; then
  sed -i -e 's/^apply_updates = no/apply_updates = yes/' \
         -e 's/^upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf || true
fi
if [ -f /usr/lib/systemd/system/dnf5-automatic.timer ]; then
  systemctl enable dnf5-automatic.timer
elif [ -f /usr/lib/systemd/system/dnf-automatic.timer ]; then
  systemctl enable dnf-automatic.timer
fi

# 7. Snapshots before transactions, so a bad update is reversible.
if command -v snapper >/dev/null 2>&1 && [ ! -d /.snapshots ]; then
  snapper -c root create-config / || true
fi

# 8. Verification gate. If a critical package silently vanished (renamed,
#    dropped from a repo, or shadowed by --ignoremissing), fail the install
#    loudly instead of shipping a broken desktop.
missing=0
for pkg in niri noctalia sddm xwayland-satellite google-chrome-stable \
           mesa-va-drivers-freeworld libva-intel-media-driver nushell; do
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    echo "MISSING REQUIRED PACKAGE: $pkg" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

# 9. Hardware decode: report, never fail. VMs and NVIDIA-only machines have no
#    VA-API device, and this spin must install there too. On Intel and AMD the
#    profile list is the thing to check after first boot (see README.md).
if ! vainfo 2>/dev/null | grep -q 'VAProfileH264High'; then
  echo "WARNING: vainfo reports no H264 profile (expected on VMs and on NVIDIA" \
       "without nvidia-vaapi-driver); check 'vainfo' after first boot" >&2
fi

%end

# --- Reboot ---------------------------------------------------------------
reboot
