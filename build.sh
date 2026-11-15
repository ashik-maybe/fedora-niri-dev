#!/usr/bin/env bash
# Build the ISO.
#
# The ISO is a stock Fedora Everything netinst with this repository's kickstart
# injected by mkksiso. Nothing is rebuilt from source. mkksiso itself needs root
# (it makes a loop device for the EFI boot image), so the script elevates that
# single command and leaves every download and the output owned by you.
#
#   ./build.sh deps       install the build dependencies (Fedora host)
#   ./build.sh base       download the netinst ISO, the repo assets and comps
#   ./build.sh check      validate the kickstart
#   ./build.sh packages   resolve + download the package tree for the offline ISO
#   ./build.sh online     build the ISO that installs from live repositories
#   ./build.sh offline    build the ISO that installs with no network at all
#   ./build.sh all        both ISOs
#   ./build.sh clean      remove out/ and build/, keep the download cache
#   ./build.sh distclean  remove out/, build/ and cache/
#
# Environment:
#   FEDORA_RELEASE  target release (default 45)
#   ARCH            target architecture (default x86_64)
#   BUILD_IMAGE     container used to resolve packages
#                   (default registry.fedoraproject.org/fedora:<release>)

set -euo pipefail
cd "$(dirname "$0")"

name="niri-dev"
release="${FEDORA_RELEASE:-45}"
arch="${ARCH:-x86_64}"
kickstart="kickstart/niri-dev.ks"
image="${BUILD_IMAGE:-registry.fedoraproject.org/fedora:${release}}"

online_iso="out/${name}-${release}-${arch}.iso"
offline_iso="out/${name}-${release}-${arch}-offline.iso"

# Packages that must never end up in the package tree. The install-time gate in
# the kickstart checks the installed system; this checks the ISO before it is
# built, which is cheaper than finding out after a 15-minute install.
expect_absent="firefox"

die() {
	echo "build: $*" >&2
	exit 1
}

# mkksiso needs several GB of scratch space. /tmp is a tmpfs on many Fedora
# installs, which is exactly where a multi-GB ISO build would run out of room.
scratch="$PWD/build/tmp"
mkdir -p "$scratch"
export TMPDIR="$scratch"

# mkksiso rebuilds the ISO's EFI boot image with mkfs.vfat, which needs a loop
# device and therefore root. Only that one command is elevated: the downloads,
# the package tree and out/ stay owned by the invoking user.
run_mkksiso() {
	if [ "$(id -u)" -eq 0 ]; then
		mkksiso "$@"
		return
	fi
	command -v sudo >/dev/null ||
		die "mkksiso needs root for its loop device (install sudo or run as root)"
	local root_scratch=/var/tmp/ks-mkksiso
	sudo rm -rf "$root_scratch"
	sudo mkdir -p "$root_scratch"
	sudo env TMPDIR="$root_scratch" mkksiso "$@"
	sudo rm -rf "$root_scratch"
}

# Files mkksiso creates while running as root come back owned by root.
reclaim() {
	[ "$(id -u)" -eq 0 ] && return 0
	sudo chown "$(id -u):$(id -g)" "$@"
}

fetch_base() {
	mkdir -p cache
	local cached directory listing iso
	cached="$(ls -1 "cache/Fedora-Everything-netinst-${arch}-${release}"-*.iso \
		2>/dev/null | sort -V | tail -1 || true)"
	if [ -n "$cached" ] && [ "${REFRESH:-0}" != 1 ]; then
		echo "using $cached (set REFRESH=1 to look for a newer one)"
		return 0
	fi
	directory="https://download.fedoraproject.org/pub/fedora/linux/releases/${release}/Everything/${arch}/iso"
	listing="$(curl -fsSL "$directory/")" || die "cannot list $directory"
	iso="$(grep -oE "Fedora-Everything-netinst-${arch}-[0-9][0-9.-]*\.iso" <<<"$listing" |
		sort -Vu | tail -1)"
	[ -n "$iso" ] || die "no netinst ISO listed at $directory"
	if [ -f "cache/$iso" ]; then
		echo "cache/$iso already present"
	else
		curl -fL --progress-bar -o "cache/$iso" "$directory/$iso"
	fi
}

fetch_assets() {
	mkdir -p cache/assets
	local asset url
	while read -r asset url; do
		if [ -s "cache/assets/$asset" ]; then
			continue
		fi
		echo "fetching $asset"
		curl -fL --progress-bar -o "cache/assets/$asset" "$url"
	done <<-EOF
		rpmfusion-free-release.noarch.rpm https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm
		rpmfusion-nonfree-release.noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm
		google-chrome.asc https://dl.google.com/linux/linux_signing_key.pub
		EOF
}

# Group expansion for the offline list needs Fedora's comps data. It lives in
# the release repository's repodata, next to the packages.
fetch_comps() {
	[ -s cache/comps.xml ] && return 0
	local os="https://download.fedoraproject.org/pub/fedora/linux/releases/${release}/Everything/${arch}/os"
	local href
	href="$(curl -fsSL "$os/repodata/repomd.xml" | python3 -c '
import sys
import xml.etree.ElementTree as ET

for node in ET.fromstring(sys.stdin.read()).iter():
    if node.get("type") != "group":
        continue
    for child in node:
        if child.tag.endswith("location"):
            print(child.get("href"))
')"
	[ -n "$href" ] || die "no comps file listed in $os/repodata/repomd.xml"
	echo "fetching comps ($href)"
	curl -fL --progress-bar -o cache/comps.raw "$os/$href"
	case "$href" in
	*.zst) zstd -dqf cache/comps.raw -o cache/comps.xml ;;
	*.gz) gzip -dc cache/comps.raw >cache/comps.xml ;;
	*) mv cache/comps.raw cache/comps.xml ;;
	esac
	rm -f cache/comps.raw
}

base_iso() {
	local base
	base="$(ls -1 "cache/Fedora-Everything-netinst-${arch}-${release}"-*.iso 2>/dev/null |
		sort -V | tail -1 || true)"
	[ -n "$base" ] || die "no netinst ISO in cache/ — run './build.sh base' first"
	printf '%s\n' "$base"
}

base() {
	fetch_base
	fetch_assets
	fetch_comps
}

check() {
	ksvalidator "$kickstart"
}

packages_stale() {
	local stamp="build/packages.list"
	[ -s "$stamp" ] || return 0
	[ -s "build/excludes.txt" ] || return 0
	[ -s packages/repodata/repomd.xml ] || return 0
	local newer
	newer="$(find "$kickstart" scripts/resolve-packages.sh \
		scripts/expand-packages.py repos -newer "$stamp" -print -quit)"
	[ -n "$newer" ]
}

fetch_packages() {
	base
	mkdir -p build
	if [ "$image" = none ]; then
		# Already inside a Fedora container of the target release (CI does
		# this, because the ISO build needs loop devices and therefore
		# privileges). Run the resolver directly instead of nesting podman.
		command -v dnf >/dev/null || die "BUILD_IMAGE=none needs dnf on this machine"
		FEDORA_RELEASE="$release" ARCH="$arch" KS="$kickstart" \
			EXPECT_ABSENT="$expect_absent" bash scripts/resolve-packages.sh
		return
	fi
	command -v podman >/dev/null || die "podman is required for './build.sh packages'"
	# The container runs the same script a developer could run by hand on a
	# machine already on the target release. :z relabels the bind mount so
	# SELinux does not deny access to the repository.
	podman run --rm \
		-v "$PWD:/work:z" -w /work \
		-e FEDORA_RELEASE="$release" \
		-e ARCH="$arch" \
		-e KS="$kickstart" \
		-e EXPECT_ABSENT="$expect_absent" \
		-e TMPDIR=/work/build/tmp \
		"$image" \
		bash -euo pipefail -c '
            dnf -y install python3 createrepo_c zstd >/dev/null
            bash scripts/resolve-packages.sh
        '
}

build_online() {
	local base
	base="$(base_iso)"
	mkdir -p out
	rm -f "$online_iso" "$online_iso.sha256"
	run_mkksiso --ks "$kickstart" --add files --add repos --add cache/assets \
		"$base" "$online_iso"
	reclaim "$online_iso"
	(cd out && sha256sum "$(basename "$online_iso")" >"$(basename "$online_iso").sha256")
	echo
	echo "built $online_iso"
	cat "$online_iso.sha256"
}

build_offline() {
	local base
	base="$(base_iso)"
	if packages_stale; then
		echo "package tree is stale or missing; resolving it first"
		fetch_packages
	else
		echo "reusing $(find packages -name '*.rpm' | wc -l) packages in packages/"
	fi

	python3 scripts/make-offline-ks.py "$kickstart" build/packages.list build/offline.ks

	mkdir -p out build/offline-marker
	: >build/offline-marker/offline
	rm -f "$offline_iso" "$offline_iso.sha256"
	run_mkksiso \
		--ks build/offline.ks \
		--add files \
		--add repos \
		--add cache/assets \
		--add packages \
		--add build/offline-marker/offline \
		"$base" "$offline_iso"
	reclaim "$offline_iso"
	(cd out && sha256sum "$(basename "$offline_iso")" >"$(basename "$offline_iso").sha256")
	echo
	echo "built $offline_iso"
	cat "$offline_iso.sha256"
}

case "${1:-}" in
deps)
	sudo dnf install -y lorax pykickstart xorriso isomd5sum podman curl zstd python3
	;;
base) base ;;
check) check ;;
packages) fetch_packages ;;
online)
	base
	check
	build_online
	;;
offline)
	base
	check
	build_offline
	;;
all)
	base
	check
	build_online
	build_offline
	;;
clean) rm -rf out build ;;
distclean) rm -rf out build cache packages ;;
*)
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
