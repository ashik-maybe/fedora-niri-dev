#!/usr/bin/env bash
# Answer "will a build on THIS machine fail for environment reasons?" before the
# heavy steps run. Every check is cheap; the expensive ones (the ~2 GB package
# download, the sudo mkksiso step) happen only after this passes.
#
# Exit status: 0 = ready (warnings may be printed), 1 = a fatal check failed.
set -uo pipefail

release="${FEDORA_RELEASE:-45}"
arch="${ARCH:-x86_64}"

fatal=0
warn=0

ok() { printf '  ok   %s\n' "$1"; }
bad() {
	printf '  FAIL %s\n' "$1"
	fatal=$((fatal + 1))
}
note() {
	printf '  warn %s\n' "$1"
	warn=$((warn + 1))
}

need() { # need <command> <what it is for>
	command -v "$1" >/dev/null 2>&1 && ok "$1 found" ||
		bad "$1 missing ($2)"
}

want() { # want <command> <what it is for>  (missing is a warning, not fatal)
	command -v "$1" >/dev/null 2>&1 && ok "$1 found" ||
		note "$1 missing ($2)"
}

gb_free() { # gb_free <path> -> free GiB as integer
	df -BG --output=avail "$1" | awk 'NR==2{print $1+0}'
}

echo "preflight: environment check for building the $release ISOs"

echo "disk:"
free_repo="$(gb_free "$PWD")"
[ "$free_repo" -ge 15 ] &&
	ok "$PWD has ${free_repo} GiB free (need 15)" ||
	bad "$PWD has only ${free_repo} GiB free; the offline build needs ~14 GiB"
free_var_tmp="$(gb_free /var/tmp)"
[ "$free_var_tmp" -ge 5 ] &&
	ok "/var/tmp has ${free_var_tmp} GiB free (mkksiso root scratch)" ||
	bad "/var/tmp has only ${free_var_tmp} GiB free; mkksiso needs ~5 GiB there"

echo "build tools:"
need podman "runs the resolver container"
need curl "downloads the netinst, assets and comps"
need zstd "unpacks comps.xml"
need python3 "runs the kickstart expander and generator"
need xorriso "test-iso.sh reads the finished ISO"
want mkksiso "built by lorax; './build.sh deps' installs it"
want lorax "provides mkksiso; './build.sh deps' installs it"
want isomd5sum "post-build media check; './build.sh deps' installs it"

echo "test tools (only needed for ./build.sh test-iso):"
want qemu-system-x86_64 "boot smoke test; './build.sh deps' installs qemu"
want socat "talks to the qemu monitor"
[ -r /usr/share/edk2/ovmf/OVMF_CODE.fd ] &&
	ok "OVMF firmware found" ||
	note "OVMF not at /usr/share/edk2/ovmf/OVMF_CODE.fd; EFI boot test will skip"
[ -e /dev/kvm ] && ok "/dev/kvm present (fast boots)" ||
	note "/dev/kvm missing; qemu falls back to TCG (slow, but works)"

echo "container:"
if podman image exists "registry.fedoraproject.org/fedora:${release}" 2>/dev/null; then
	ok "fedora:${release} image present"
else
	echo "  pulling registry.fedoraproject.org/fedora:${release} ..."
	podman pull "registry.fedoraproject.org/fedora:${release}" >/dev/null 2>&1 &&
		ok "fedora:${release} image pulled" ||
		bad "cannot pull registry.fedoraproject.org/fedora:${release}"
fi

echo "network:"
while read -r label url; do
	[ -z "$label" ] && continue
	code="$(curl -fsSI -o /dev/null -w '%{http_code}' --max-time 15 "$url" 2>/dev/null)"
	case "${code:-000}" in
	200 | 301 | 302 | 303 | 307 | 308) ok "$label reachable ($code)" ;;
	*) bad "$url not reachable (http $code)" ;;
	esac
done <<-EOF
	fedora-mirror	https://download.fedoraproject.org/pub/fedora/linux/releases/${release}/Everything/${arch}/iso/
	rpmfusion-free	https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm
	rpmfusion-nonfree	https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm
	chrome-repo	https://dl.google.com/linux/chrome/rpm/stable/x86_64/repodata/repomd.xml
	helium-copr	https://download.copr.fedorainfracloud.org/results/imput/helium/fedora-${release}-${arch}/repodata/repomd.xml
EOF

echo "privileges:"
if [ "$(id -u)" -eq 0 ]; then
	ok "running as root (mkksiso needs it)"
elif sudo -n true 2>/dev/null; then
	ok "passwordless sudo available"
else
	note "sudo will ask for a password (./build.sh deps and the single mkksiso step)"
fi

echo
if [ "$fatal" -gt 0 ]; then
	echo "preflight: $fatal fatal problem(s); fix them before './build.sh offline'"
	exit 1
fi
echo "preflight: ready ($warn warning(s); warnings do not block the build)"
