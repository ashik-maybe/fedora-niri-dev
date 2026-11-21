#!/usr/bin/env bash
# Test a built ISO before you install it:
#
#   1. content  the injected kickstart is inside, ksvalidator passes on it,
#               the offline ISO's embedded repo path is correct, the repo
#               label the boot loader references matches the ISO's own label
#   2. serial   kernel + initrd boot with console=ttyS0; Anaconda must start
#               (proves stage2 is found on the ISO and the kickstart parses)
#   3. efi      OVMF boot + screendumps; the frame must show signs of life
#               (proves the ISO's rewritten EFI loader works)
#
# A full install needs your machine and virt-manager; this catches the cheap
# ways the ISO can be broken first. Run ./build.sh deps-test for qemu + OVMF.
#
# Usage: scripts/test-iso.sh [PATH-TO-ISO] [--no-efi] [--no-serial]
set -uo pipefail

iso=""
efi=1
serial=1
for arg in "$@"; do
	case "$arg" in
	--no-efi) efi=0 ;;
	--no-serial) serial=0 ;;
	-h | --help)
		sed -n '2,20p' "$0"
		exit 0
		;;
	-*)
		echo "test-iso: unknown flag $arg" >&2
		exit 2
		;;
	*) iso="$arg" ;;
	esac
done

if [ -z "$iso" ]; then
	iso="$(ls -1t out/*.iso 2>/dev/null | head -1 || true)"
	[ -n "$iso" ] || {
		echo "test-iso: no ISO path given and out/ has none; build one first" >&2
		exit 2
	}
fi
[ -f "$iso" ] || {
	echo "test-iso: no such ISO: $iso" >&2
	exit 2
}
iso="$(readlink -f "$iso")"
echo "test-iso: $iso ($(du -h "$iso" | cut -f1))"

command -v xorriso >/dev/null || {
	echo "test-iso: xorriso missing (./build.sh deps)" >&2
	exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail=0
note_fail() {
	echo "  FAIL $1"
	fail=$((fail + 1))
}
pass() { echo "  PASS $1"; }

volid="$(xorriso -indev "$iso" -pvd_info 2>/dev/null | awk '/^Volume Id /{print $NF}')"
[ -n "$volid" ] || {
	echo "test-iso: cannot read the ISO's volume id" >&2
	exit 1
}
echo "test-iso: volume id $volid"

is_offline=0
case "$(basename "$iso")" in
*-offline*) is_offline=1 ;;
esac

root_ls() { xorriso -indev "$iso" -ls / 2>/dev/null | tr -d "'"; }

echo
echo "== content"

ks_name="$(root_ls | grep -E '\.ks$' | head -1)"
if [ -z "$ks_name" ]; then
	note_fail "no .ks at the ISO root (the kickstart was never injected)"
else
	pass "kickstart at ISO root: /$ks_name"
fi

if [ -n "$ks_name" ]; then
	xorriso -osirrox on -indev "$iso" -extract "/$ks_name" "$work/$ks_name" >/dev/null 2>&1
	if command -v ksvalidator >/dev/null; then
		if ksvalidator -i Fedora "$work/$ks_name" >/dev/null 2>&1; then
			pass "embedded kickstart passes ksvalidator"
		else
			note_fail "embedded kickstart does not pass ksvalidator"
		fi
	else
		echo "  note ksvalidator missing; skipping (./build.sh deps)"
	fi
	if [ "$is_offline" -eq 1 ]; then
		if grep -qF 'file:///run/install/repo/packages' "$work/$ks_name"; then
			pass "offline repo points at the embedded tree"
		else
			note_fail "offline kickstart does not use file:///run/install/repo/packages"
		fi
		if grep -qE '^repo .*baseurl=https?://' "$work/$ks_name"; then
			note_fail "offline kickstart still has a remote repo line"
		else
			pass "no remote repo lines in the offline kickstart"
		fi
	fi
fi

if [ "$is_offline" -eq 1 ]; then
	if xorriso -indev "$iso" -ls /packages/repodata 2>/dev/null | grep -q 'repomd.xml'; then
		pass "embedded package repo indexed (packages/repodata/repomd.xml)"
	else
		note_fail "packages/repodata/repomd.xml missing from the offline ISO"
	fi
fi

for dir in files repos assets; do
	root_ls | grep -qE "^${dir}(/|$)" &&
		pass "/$dir present" ||
		note_fail "/$dir missing from the ISO"
done

if root_ls | grep -qE '^assets(/|$)'; then
	n="$(xorriso -indev "$iso" -ls /assets 2>/dev/null | grep -cE 'rpm|\.asc' || true)"
	[ "$n" -ge 3 ] &&
		pass "/assets has $n files (RPM Fusion release RPMs + Chrome key)" ||
		note_fail "/assets has only $n files; the RPM Fusion/Chrome assets are missing"
fi

grub_cfg=""
for candidate in /EFI/BOOT/grub.cfg /boot/grub2/grub.cfg /boot/grub/grub.cfg; do
	if xorriso -indev "$iso" -ls "${candidate%/*}" 2>/dev/null | grep -q "$(basename "$candidate")"; then
		grub_cfg="$candidate"
		break
	fi
done
if [ -n "$grub_cfg" ]; then
	xorriso -osirrox on -indev "$iso" -extract "$grub_cfg" "$work/grub.cfg" >/dev/null 2>&1
	if grep -qF "LABEL=$volid" "$work/grub.cfg"; then
		pass "boot config references the ISO's own volume label ($volid)"
	else
		note_fail "boot config does not reference LABEL=$volid (mismatch between the ISO label and the boot entries)"
	fi
else
	note_fail "no grub.cfg found in the ISO"
fi

if [ "$serial" -eq 1 ]; then
	echo
	echo "== boot (serial console)"
	xorriso -osirrox on -indev "$iso" \
		-extract /images/pxeboot/vmlinuz "$work/vmlinuz" \
		-extract /images/pxeboot/initrd.img "$work/initrd.img" >/dev/null 2>&1
	if [ ! -s "$work/vmlinuz" ] || [ ! -s "$work/initrd.img" ]; then
		note_fail "cannot extract /images/pxeboot/{vmlinuz,initrd.img}"
	else
		ks_arg=""
		[ -n "$ks_name" ] && ks_arg=" inst.ks=hd:LABEL=$volid:/$ks_name"
		qemu-system-x86_64 -name test-iso -m 2048 -enable-kvm \
			-kernel "$work/vmlinuz" -initrd "$work/initrd.img" \
			-append "inst.stage2=hd:LABEL=$volid$ks_arg console=ttyS0,115200n8" \
			-cdrom "$iso" -display none \
			-serial file:"$work/serial.log" -pidfile "$work/qemu.pid" \
			>/dev/null 2>&1 &
		qpid=$!
		elapsed=0
		serial_rc=2
		while [ "$elapsed" -lt 180 ]; do
			sleep 5
			elapsed=$((elapsed + 5))
			if grep -qE 'Starting installer|\[anaconda\]' "$work/serial.log" 2>/dev/null; then
				serial_rc=0
				break
			fi
			if grep -qE 'Kernel panic|dracut-initqueue.*timeout|Could not boot|Dracut Emergency|Kickstart (syntax )?[Ee]rror|Failed to read kickstart|error parsing kickstart' "$work/serial.log" 2>/dev/null; then
				serial_rc=1
				break
			fi
			kill -0 "$qpid" 2>/dev/null || break
		done
		kill "$qpid" 2>/dev/null
		wait "$qpid" 2>/dev/null
		case "$serial_rc" in
		0) pass "Anaconda started from the ISO (serial, ${elapsed}s)" ;;
		1)
			note_fail "fatal boot error on serial:"
			grep -E 'Kernel panic|dracut-initqueue.*timeout|Could not boot|Dracut Emergency|[Kk]ickstart.*[Ee]rror|Failed to read kickstart|error parsing kickstart' "$work/serial.log" | head -5 >&2
			;;
		*)
			note_fail "no Anaconda start and no kernel panic within 180s"
			tail -5 "$work/serial.log" >&2 || true
			;;
		esac
	fi
fi

if [ "$efi" -eq 1 ]; then
	echo
	echo "== boot (EFI, OVMF)"
	if [ ! -r /usr/share/edk2/ovmf/OVMF_CODE.fd ]; then
		echo "  note OVMF firmware not found; skipping EFI test"
	else
		qemu-system-x86_64 -name test-iso-efi -m 2048 -enable-kvm \
			-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
			-cdrom "$iso" -vga std -display none -vnc 127.0.0.1:29 \
			-monitor unix:"$work/monitor.sock",server,nowait \
			>/dev/null 2>&1 &
		qpid=$!
		efi_rc=1
		for t in 20 40 60 80 100 120; do
			sleep $((t == 20 ? 20 : t - prev_t))
			prev_t=$t
			printf 'screendump %s/shot-%s.ppm\n' "$work" "$t" |
				socat - UNIX-CONNECT:"$work/monitor.sock" >/dev/null 2>&1
			sleep 1
			stats="$(
				python3 - "$work/shot-$t.ppm" "$work/shot-$((t - 20)).ppm" <<'PY'
import sys
try:
    d = open(sys.argv[1], 'rb').read()
    px = d.split(b'\n', 3)[3]
    nonzero = sum(1 for b in px if b != 0)
    total = len(px)
    changed = 0
    try:
        p = open(sys.argv[2], 'rb').read().split(b'\n', 3)[3]
        changed = sum(1 for a, b in zip(px, p) if a != b)
    except Exception:
        pass
    print(f"{nonzero} {total} {changed}")
except FileNotFoundError:
    print("0 0 0")
PY
			)"
			read -r nonzero total changed <<<"$stats"
			if [ "$total" -gt 0 ] && { [ "$((nonzero * 1000 / total))" -gt 5 ] || [ "$changed" -gt 1000 ]; }; then
				efi_rc=0
				break
			fi
			kill -0 "$qpid" 2>/dev/null || break
		done
		kill "$qpid" 2>/dev/null
		wait "$qpid" 2>/dev/null
		[ "$efi_rc" -eq 0 ] &&
			pass "EFI boot produced a live frame (found via OVMF + screendump)" ||
			note_fail "EFI boot showed a static black frame for 120s"
	fi
fi

echo
if [ "$fail" -gt 0 ]; then
	echo "test-iso: $fail check(s) failed"
	exit 1
fi
echo "test-iso: all checks passed; install it in virt-manager as usual"
