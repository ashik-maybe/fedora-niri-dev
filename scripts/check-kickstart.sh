#!/usr/bin/env bash
# Validate the kickstart, and check the shell inside it.
#
# ksvalidator only proves the kickstart's syntax. The `%post` sections are shell
# scripts that Anaconda runs after the install, and a typo there does not fail
# validation: it fails a 15-minute install, half way through, on the machine
# being installed. `bash -n` on each extracted block catches that in a second.
set -euo pipefail

kickstart="${1:-kickstart/gnome-devstation.ks}"
[ -f "$kickstart" ] || {
	echo "check: no such kickstart: $kickstart" >&2
	exit 1
}
command -v ksvalidator >/dev/null || {
	echo "check: ksvalidator is missing (dnf install pykickstart)" >&2
	exit 1
}

ksvalidator "$kickstart"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# %pre and %post are both shell. Everything between the header line and %end is
# the script, byte for byte, so the check is on what Anaconda will actually run.
python3 - "$kickstart" "$work" <<'PY'
import pathlib
import sys

kickstart, work = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
blocks, current, inside = [], [], False

for line in kickstart.read_text().splitlines():
    stripped = line.strip()
    if stripped.startswith("%pre") or stripped.startswith("%post"):
        inside, current = True, []
        continue
    if inside and stripped == "%end":
        inside = False
        blocks.append(current)
        continue
    if inside:
        current.append(line)

if inside:
    raise SystemExit(f"{kickstart}: unterminated %pre/%post section")

for number, block in enumerate(blocks, start=1):
    (work / f"block-{number}.sh").write_text("\n".join(block) + "\n")

print(f"check: {len(blocks)} %pre/%post blocks extracted")
PY

status=0
for script in "$work"/block-*.sh; do
	[ -e "$script" ] || continue
	if ! bash -n "$script"; then
		echo "check: $(basename "$script") has a shell syntax error" >&2
		status=1
	fi
done

[ "$status" -eq 0 ] || exit 1
echo "check: kickstart valid, embedded shell parses"
