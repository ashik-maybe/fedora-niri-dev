# Testing

Four gates run without a VM. One gate needs a booted image. Run them in this
order; each one is cheap until the last.

## 1. Shell and Python syntax

```bash
bash -n build.sh scripts/*.sh files/niri-glue.sh
python3 -m py_compile scripts/*.py
```

Both commands must exit 0.

## 2. The glue script against the packaged keymap

```bash
bash scripts/test-niri-glue.sh
```

The script extracts `usr/share/doc/niri/default-config.kdl` from the newest
`packages/niri-*.rpm` and runs `files/niri-glue.sh` against it. It must print:

```
test-niri-glue: patched and verified against packages/niri-<version>.x86_64.rpm (<version>)
```

This proves the `sed` patterns still match the packaged keymap. It fails on an
upstream rename, which is the intended behaviour.

## 3. Kickstart validation

`ksvalidator` comes from `pykickstart`. Run it in a container so the host does
not need the tool:

```bash
podman run --rm -v "$PWD":/repo:ro -w /repo \
  registry.fedoraproject.org/fedora:45 \
  bash -lc 'dnf -y install pykickstart >/dev/null && bash scripts/check-kickstart.sh kickstart/niri-dev.ks'
```

It must print:

```
check: 2 %pre/%post blocks extracted
check: kickstart valid, embedded shell parses
```

## 4. Offline package tree

```bash
./build.sh packages
```

The resolver runs in a `fedora:$FEDORA_RELEASE` container. It must resolve the
whole closure against an empty install root, then prove the result with
`--disablerepo='*'`. A dependency problem or an empty transaction fails the
step.

`build/packages.list` must be newer than `kickstart/niri-dev.ks`. If it is
older, `packages_stale()` will re-resolve on the next offline build.

## 5. Booted image

```bash
./build.sh deps
./build.sh deps-test
./build.sh offline
./build.sh test-iso
```

`test-iso` proves the ISO content, the serial stage2 boot and the EFI loader.
It does not prove an install. Install the image in a VM, then run the checks
below.

### After install

```bash
# The shell unit is active and ordered correctly.
systemctl --user is-active noctalia.service        # active
journalctl --user -b | grep -i 'ordering cycle'    # no output

# The generated keymap is in place and no stock bind survives.
grep -c '^// spawn-at-startup "waybar"' /etc/niri/config.kdl     # 1
grep -nE 'spawn "(alacritty|fuzzel|swaylock)"' /etc/niri/config.kdl   # no output

# The package set matches the kickstart.
rpm -q gnome-keyring-pam                           # installed
rpm -q evolution-data-server                       # not installed
```

### Key presses

These need a human at the keyboard. There is no input injection in the test
harness, so do not record them as passed without pressing them.

| Keys | Expected |
|---|---|
| `Mod+T` | ptyxis opens |
| `Mod+D` | the Noctalia launcher opens |
| `Super+Alt+L` | the Noctalia lock screen appears |

## What this does not cover

- Hardware-specific behaviour (suspend, Wi-Fi, brightness).
- NVIDIA module load. Check `journalctl -b | grep akmod` after install.
- Secure Boot MOK enrolment.
