#!/usr/bin/env bash
# Prove files/niri-glue.sh patches the real packaged keymap without
# installing niri: extract usr/share/doc/niri/default-config.kdl from the
# newest packages/niri-*.rpm into a temp dir and run the glue against it.
set -euo pipefail

cd "$(dirname "$0")/.."

# Newest niri rpm in packages/ by mtime; none means the test cannot run.
rpm=$(ls -t packages/niri-*.rpm 2>/dev/null | head -n1 || true)
[ -n "$rpm" ] || {
	echo "test-niri-glue: no packages/niri-*.rpm found" >&2
	exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rpm2cpio "$rpm" | (cd "$tmp" && cpio -idm --quiet)

version=$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$rpm" 2>/dev/null || basename "$rpm" .rpm)

SRC="$tmp/usr/share/doc/niri/default-config.kdl" DST="$tmp/config.kdl" bash files/niri-glue.sh

cfg="$tmp/config.kdl"

# niri reads the system config as the session user, so 0600 from mktemp
# would make the whole glue patch useless.
mode=$(stat -c %a "$cfg")
[ "$mode" = 644 ] || {
	echo "test-niri-glue: expected config mode 0644, got $mode" >&2
	exit 1
}

assert_has() {
	grep -Fq "$1" "$cfg" || {
		echo "test-niri-glue: expected config to contain: $1" >&2
		exit 1
	}
}

assert_lacks() {
	! grep -Fq "$1" "$cfg" || {
		echo "test-niri-glue: expected config NOT to contain: $1" >&2
		exit 1
	}
}

assert_has 'spawn "ptyxis"'
assert_has 'panel-toggle launcher'
assert_has 'session lock'
assert_has '// spawn-at-startup "waybar"'
assert_lacks 'spawn "alacritty"'
assert_lacks 'spawn "fuzzel"'
assert_lacks 'spawn "swaylock"'

echo "test-niri-glue: patched and verified against $rpm ($version)"
