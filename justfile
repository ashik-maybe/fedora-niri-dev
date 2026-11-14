# niri-dev — build tooling
#
# The ISO is a stock Fedora Everything netinst with this repo's kickstart
# injected by mkksiso. Nothing is rebuilt from source, nothing needs root, and
# nothing is snapshotted: the package set resolves from live repositories when
# the installed system runs for the first time.
#
# Usage:
#   just deps          install build dependencies (lorax, pykickstart, ...)
#   just fetch-base    download the Fedora netinst ISO into cache/
#   just build         validate, then produce out/niri-dev-<release>-x86_64.iso
#   just clean         remove build output
#
# Override the target release:
#   FEDORA_RELEASE=46 just fetch-base build

set shell := ["bash", "-euo", "pipefail", "-c"]

fedora_release := env_var_or_default("FEDORA_RELEASE", "45")
arch := "x86_64"

base_name := "Fedora-Everything-netinst-" + arch + "-" + fedora_release
output := "out/niri-dev-" + fedora_release + "-" + arch + ".iso"

# List available recipes
default:
    @just --list

# Install the build dependencies on a Fedora host
deps:
    sudo dnf install -y lorax pykickstart xorriso isomd5sum

# Validate the kickstart syntax
check:
    ksvalidator kickstart/niri-dev.ks

# Download the Fedora Everything netinst base image into cache/
fetch-base:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p cache
    dir="https://download.fedoraproject.org/pub/fedora/linux/releases/{{fedora_release}}/Everything/{{arch}}/iso"
    iso="$(curl -fsSL "$dir/" \
        | grep -oE 'Fedora-Everything-netinst-x86_64-[0-9.]+\.iso' \
        | sort -Vu | tail -1)"
    if [ -z "$iso" ]; then
        echo "no netinst ISO listed at $dir" >&2
        exit 1
    fi
    if [ ! -f "cache/$iso" ]; then
        curl -fL --progress-bar -o "cache/$iso" "$dir/$iso"
    else
        echo "cache/$iso already present"
    fi
    echo "cache/$iso"

# Build the ISO into out/
build: check
    #!/usr/bin/env bash
    set -euo pipefail
    base="$(ls -1 cache/{{base_name}}-*.iso 2>/dev/null | sort -V | tail -1 || true)"
    if [ -z "$base" ]; then
        echo "no base ISO in cache/ — run 'just fetch-base' first" >&2
        exit 1
    fi
    mkdir -p out
    rm -f "{{output}}"
    # --add puts each path at the ISO root with its basename, which is why the
    # kickstart reads /run/install/repo/files and /run/install/repo/repos.
    mkksiso \
        --ks kickstart/niri-dev.ks \
        --add files \
        --add repos \
        "$base" "{{output}}"
    echo
    echo "built {{output}}"
    sha256sum "{{output}}"

# Remove build output
clean:
    rm -rf out

# Remove build output and the cached base ISO
distclean: clean
    rm -rf cache
