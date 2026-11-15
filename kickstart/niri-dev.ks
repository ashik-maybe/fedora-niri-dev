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

# RPM Fusion nonfree is enabled and used for exactly one package: unrar. The
# rest of nonfree is there for what users add later (akmod-nvidia, the media
# extras). Fedora 45 provides libva-intel-media-driver itself, so the Intel
# VA-API backend no longer needs a nonfree package at install time.

repo --name="rpmfusion-nonfree" --baseurl=https://download1.rpmfusion.org/nonfree/fedora/releases/$releasever/Everything/$basearch/os/

repo --name="rpmfusion-nonfree-updates" --baseurl=https://download1.rpmfusion.org/nonfree/fedora/updates/$releasever/$basearch/

# --- Packages -------------------------------------------------------------
%packages --ignoremissing

@core
@standard

# The kernel is listed, not implied.
#
# Anaconda only adds `kernel` to the transaction if it can resolve it from an
# enabled repository (get_kernel_package() in pyanaconda). When it cannot, it
# logs "No such package: kernel" and carries on installing without one. The
# online ISO never notices, because Fedora's own repos carry it. The offline
# ISO installs from its embedded package tree and nothing else, so a tree
# resolved from a kickstart that never mentions the kernel contains no kernel
# rpm at all -- and the resulting install cannot boot. Listing it here is what
# puts the kernel into that tree.
kernel

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
iwlbluetooth-firmware
realtek-firmware
mt7xxx-firmware
amd-ucode-firmware
microcode_ctl
fwupd
gnome-firmware

# Optional hardware, not in the default set
#
# kernel-modules-extra is a separate package from kernel-modules: it is the
# long tail of sensors, old radios, niche card readers and other devices that
# the main module set does not carry. Fedora's Workstation does not install it;
# a catch-all image does, at ~3 MB.
kernel-modules-extra

# --- NVIDIA driver -------------------------------------------------
#
# RPM Fusion's akmod-nvidia builds the kernel module at install time and
# rebuilds it on every kernel update, so it needs the build toolchain and the
# matching kernel-devel in the same transaction. That is why gcc, make,
# kernel-headers and glibc-devel are listed rather than implied: on an offline
# ISO there is no second dnf pass to fetch them, and a missing build dep fails
# the install instead of shipping a broken driver. kernel-devel pins the
# exact kernel version the tree contains, so the module always matches.
akmod-nvidia
kernel-devel
gcc
make
kernel-headers
glibc-devel

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

# --- Graphics ------------------------------------------------------
#
# mesa-va-drivers-freeworld lives in the codecs section below because it is
# the AMD video decode stack, not a graphics driver. libva-intel-* covers
# Intel; both are present so the image does not need to know which GPU it
# lands on.

# Codecs (RPM Fusion)
#
# ffmpeg is listed here, not swapped in afterwards. Resolution testing showed
# RPM Fusion's ffmpeg-libs satisfies every libavcodec/libavformat requirement in
# the transaction, so ffmpeg-free is never selected and the whole set resolves
# in one pass. That is also what makes the offline ISO possible: no
# post-install dnf transaction needs a repository.
#
# Deliberately absent: mesa-vdpau-drivers-freeworld. It no longer exists as a
# separate package on Fedora 45; mesa-va-drivers-freeworld obsoletes it.
#
# GStreamer is listed explicitly because WebRTC in Chrome, screen recording and
# the Nautilus video thumbnails all go through it. The VA-API plugin needs no
# package of its own: libgstva.so ships inside gstreamer1-plugins-bad-free.
#
# The -freeworld packages are additive on Fedora 45, not replacements: verified
# with repoquery, they declare no Conflicts and share no plugin files with the
# -free packages above. libheif-freeworld only adds the HEVC/AV1/x264/x265
# codec plugins and pulls Fedora's libheif in as a dependency.
libva-intel-media-driver
libva-intel-driver
mesa-va-drivers-freeworld
gstreamer1-plugins-good
gstreamer1-plugins-bad-free
gstreamer1-plugins-bad-freeworld
gstreamer1-plugins-ugly
gstreamer1-plugins-ugly-free
gstreamer1-plugin-libav
gstreamer1-plugin-openh264
gstreamer1-plugin-dav1d
libheif-freeworld
unrar
ffmpeg

# Media
#
# vlc is Fedora's own build as of Fedora 45; RPM Fusion adds the codec plugins
# on top, which is where DVD, Blu-ray and the remaining formats come from.
vlc
vlc-plugins-freeworld
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

# AppImage support
#
# AppImage runtimes differ. The classic one dlopens libfuse.so.2 and fails with
# "dlopen(): error loading libfuse.so.2" when it is missing; newer ones can use
# libfuse3 (Fedora ships that) or bundle FUSE statically. Only the classic one
# needs anything from us, and it is still the most common one in the wild.
#
# Both packages are required: `fuse` needs only `fuse-common`, not `fuse-libs`,
# so it installs `fusermount` and leaves the library out. Neither package
# conflicts with fuse3.
fuse
fuse-libs

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
# gcc and make ship via the NVIDIA toolchain block above (same transaction)
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

# Assets fetched at build time (see build.sh): RPM Fusion's release packages and
# Chrome's signing key. They are copied into the installed system here
# because the ISO mount is not guaranteed to be visible inside the chrooted
# %post, and because the install must work with the network unplugged.
assets=/run/install/repo/assets
for f in rpmfusion-free-release.noarch.rpm rpmfusion-nonfree-release.noarch.rpm \
         google-chrome.asc; do
  install -Dm0644 "$assets/$f" "$root/var/tmp/ks-assets/$f"
done

# Marker written by `build.sh offline`. The chrooted %post uses it to skip the
# steps that can only work with a network.
if [ -e /run/install/repo/offline ]; then
  install -Dm0644 /run/install/repo/offline "$root/var/tmp/ks-assets/offline"
fi

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

# 0. Is this the offline ISO? build.sh marks it, and the only steps that need a
#    network (Flathub) are skipped instead of timing out.
offline=0
if [ -e /var/tmp/ks-assets/offline ]; then
  offline=1
fi

# 1. Persist the third-party repositories for the installed system.
#    The `repo` lines above only configure the installer, and Anaconda writes
#    them into /etc/yum.repos.d as a side effect. Drop those generated files
#    first: the release packages below ship the maintained, signed versions, and
#    leaving both would duplicate sections.
#
#    The release packages come from the ISO (copied by %post --nochroot), and
#    `rpm -Uvh` is deliberate: their only dependencies are already installed, so
#    this needs no repository metadata and works with no network. --nosignature
#    is the chicken-and-egg: the key that signs these packages ships inside
#    them, and their only content is repository definitions and that key.
rm -f /etc/yum.repos.d/rpmfusion-free.repo \
      /etc/yum.repos.d/rpmfusion-free-updates.repo \
      /etc/yum.repos.d/rpmfusion-nonfree.repo \
      /etc/yum.repos.d/rpmfusion-nonfree-updates.repo \
      /etc/yum.repos.d/ks-offline.repo

rpm -Uvh --nosignature /var/tmp/ks-assets/rpmfusion-free-release.noarch.rpm \
         /var/tmp/ks-assets/rpmfusion-nonfree-release.noarch.rpm

# Chrome's repo file is shipped on the ISO, so trust its signing key up front
# instead of letting the first `dnf upgrade` stop for a key prompt. The copy on
# the ISO is what makes that work offline.
rpm --import /var/tmp/ks-assets/google-chrome.asc

# 2. Graphical boot by default, with SDDM as the greeter.
systemctl set-default graphical.target
systemctl enable sddm.service

# 3. Flathub, and the Flatpaks this image standardises on. Both steps need
#    network and a working /var inside the chroot; if either is flaky, warn and
#    move on rather than failing an otherwise good install.
if [ "$offline" -eq 1 ]; then
  echo "offline ISO: skipping Flathub; install Flatseal and Gear Lever after first boot" >&2
else
  flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo || \
    echo "WARNING: could not add the flathub remote" >&2
  for app in com.github.tchx84.Flatseal it.mijorus.gearlever; do
    flatpak install -y --system flathub "$app" || \
      echo "WARNING: $app not preinstalled; run 'flatpak install flathub $app' after first boot" >&2
  done
fi

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
           mesa-va-drivers-freeworld libva-intel-media-driver nushell \
           ffmpeg vlc-plugins-freeworld gstreamer1-plugins-bad-freeworld \
           gstreamer1-plugins-ugly-free rpmfusion-free-release fuse \
           kernel akmod-nvidia kernel-devel gcc make kernel-headers glibc-devel \
           kernel-modules-extra; do
  if ! rpm -q "$pkg" >/dev/null 2>&1; then
    echo "MISSING REQUIRED PACKAGE: $pkg" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

# The AppImage runtime dlopens this exact soname, so check the library rather
# than trusting the package name.
if ! ldconfig -p | grep -q 'libfuse\.so\.2'; then
  echo "MISSING LIBFUSE.SO.2: AppImages will not run" >&2
  exit 1
fi

# 9. Hardware decode: report, never fail. VMs and NVIDIA-only machines have no
#    VA-API device, and this spin must install there too. On Intel and AMD the
#    profile list is the thing to check after first boot (see README.md).
if ! vainfo 2>/dev/null | grep -q 'VAProfileH264High'; then
  echo "WARNING: vainfo reports no H264 profile (expected on VMs and on" \
       "NVIDIA without a VA-API backend); check 'vainfo' after first boot" >&2
fi

# 10. The build assets have been consumed. Leaving them behind would put RPM
#     Fusion's release files and Chrome's key in /var/tmp forever.
rm -rf /var/tmp/ks-assets

%end

# --- Reboot ---------------------------------------------------------------
reboot
