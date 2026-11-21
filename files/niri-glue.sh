#!/bin/sh
# niri-glue: point a copy of niri's packaged default config at noctalia.
#
# The packaged default starts waybar, binds Mod+T to alacritty, Mod+D to
# fuzzel and Super+Alt+L to swaylock; this image installs ptyxis and
# noctalia instead, so those stock binds are dead. We write the patched
# copy to $dst so niri starts noctalia: niri loads /etc/niri/config.kdl
# only when ~/.config/niri/config.kdl is absent.

set -eu

src=${SRC:-/usr/share/doc/niri/default-config.kdl}
dst=${DST:-/etc/niri/config.kdl}

if [ ! -f "$src" ]; then
	# A packaging move must not fail the install; warn and skip.
	echo "niri-glue: $src not found, nothing to patch" >&2
	exit 0
fi

# niri reads the user config only when the system one is absent, so the
# parent dir must exist before the patched copy lands there.
mkdir -p "$(dirname "$dst")"

# Write beside the target and rename into place. A sed that dies midway must
# not leave a truncated config that the install gate would still accept.
tmp=$(mktemp "$dst.XXXXXX")
trap 'rm -f "$tmp"' EXIT

sed -e 's|^spawn-at-startup "waybar"|// spawn-at-startup "waybar"|' \
	-e 's|{ spawn "alacritty"; }|{ spawn "ptyxis"; }|' \
	-e 's|Open a Terminal: alacritty|Open a Terminal: ptyxis|' \
	-e 's|{ spawn "fuzzel"; }|{ spawn-sh "noctalia msg panel-toggle launcher"; }|' \
	-e 's|Run an Application: fuzzel|Run an Application: Noctalia|' \
	-e 's|{ spawn "swaylock"; }|{ spawn-sh "noctalia msg session lock"; }|' \
	-e 's|Lock the Screen: swaylock|Lock the Screen|' \
	"$src" >"$tmp"

mv "$tmp" "$dst"

# The patched copy is useless if a stock tool still runs from it.
assert_has() {
	grep -Fq "$1" "$dst" || {
		echo "niri-glue: dst missing expected content: $1" >&2
		exit 1
	}
}

assert_lacks() {
	! grep -Fq "$1" "$dst" || {
		echo "niri-glue: dst still contains: $1" >&2
		exit 1
	}
}

assert_has '// spawn-at-startup "waybar"'
assert_has 'spawn "ptyxis"'
assert_has 'panel-toggle launcher'
assert_has 'session lock'
assert_lacks 'spawn "alacritty"'
assert_lacks 'spawn "fuzzel"'
assert_lacks 'spawn "swaylock"'
