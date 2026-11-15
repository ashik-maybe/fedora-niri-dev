#!/usr/bin/env bash
# Resolve the kickstart against live repositories and download every RPM it
# needs into $DEST, indexed as a dnf repository.
#
# build.sh runs this inside a Fedora container of the target release, so the
# closure matches that release rather than whatever the build host runs. It can
# also be run directly on a machine that is already on the target release:
# nothing here touches the host's rpmdb (--installroot is an empty directory).
#
# Environment:
#   FEDORA_RELEASE  release to resolve against (default 45)
#   KS              kickstart to read (default kickstart/gnome-devstation.ks)
#   DEST            output directory (default packages)
#   COMPOS          comps.xml for group expansion (default cache/comps.xml)
#   ASSETS          directory with the release RPMs (default cache/assets)
#   EXPECT_ABSENT   space-separated packages that must not be downloaded

set -euo pipefail

release="${FEDORA_RELEASE:-45}"
kickstart="${KS:-kickstart/gnome-devstation.ks}"
dest="${DEST:-packages}"
compos="${COMPOS:-cache/comps.xml}"
assets="${ASSETS:-cache/assets}"
expect_absent="${EXPECT_ABSENT:-}"

die() {
	echo "resolve-packages: $*" >&2
	exit 1
}

[ -f "$compos" ] || die "missing $compos (run './build.sh base' first)"
for asset in rpmfusion-free-release.noarch.rpm rpmfusion-nonfree-release.noarch.rpm; do
	[ -f "$assets/$asset" ] || die "missing $assets/$asset (run './build.sh base' first)"
done

# The repositories the kickstart itself uses. RPM Fusion comes from its release
# packages, Chrome and Helium from the repo files this repository ships.
# --nosignature is the chicken-and-egg: the key that signs these packages lives
# inside them. They arrive over HTTPS from the project's own mirror, and their
# only content is repository definitions.
rpm -Uvh --nosignature "$assets/rpmfusion-free-release.noarch.rpm" \
	"$assets/rpmfusion-nonfree-release.noarch.rpm"
for repo in repos/*.repo; do
	install -Dm0644 "$repo" "/etc/yum.repos.d/$(basename "$repo")"
done
dnf -q makecache

mkdir -p build
python3 scripts/expand-packages.py "$kickstart" "$compos" \
	build/packages.list build/excludes.txt

rm -rf /tmp/ks-root /tmp/ks-cache "$dest"
mkdir -p /tmp/ks-root "$dest"

mapfile -t install_list <build/packages.list
excludes="$(paste -sd, build/excludes.txt)"

# --installroot points at an empty directory, so the transaction is the set an
# installation would produce, not a delta against this container.
# --downloadonly stops dnf before it touches that directory.
if ! dnf -y install --installroot=/tmp/ks-root --use-host-config \
	--releasever="$release" --downloadonly --setopt=cachedir=/tmp/ks-cache \
	"${install_list[@]}" --exclude="$excludes" >/tmp/ks-resolve.log 2>&1; then
	echo "resolve-packages: the transaction did not resolve:" >&2
	grep -E "^Problem|^Failed|No match|no package" /tmp/ks-resolve.log | head -20 >&2
	exit 1
fi

find /tmp/ks-cache -name '*.rpm' -exec cp -n -t "$dest" {} +
createrepo_c --quiet "$dest"

rpms="$(find "$dest" -name '*.rpm' | wc -l)"
[ "$rpms" -gt 500 ] || die "only $rpms packages downloaded; refusing to call that an ISO"

echo "resolved $rpms packages into $dest ($(du -sh "$dest" | cut -f1))"

# A trim that quietly came back is the failure this check exists to catch: it
# would be embedded in the ISO, and the install-time gate would only catch it
# after the user had already waited through the whole install.
missing=0
for package in $expect_absent; do
	if compgen -G "$dest/$package-[0-9]*.rpm" >/dev/null; then
		echo "resolve-packages: $package should be trimmed but was downloaded" >&2
		missing=1
	fi
done
[ "$missing" -eq 0 ] || exit 1
