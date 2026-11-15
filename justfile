# niri-dev — build tooling
#
# Thin wrappers around ./build.sh, so the same steps work when `just` is not
# installed (CI does that) and stay readable here.
#
# Usage:
#   just deps           install build dependencies (lorax, pykickstart, podman)
#   just fetch-base     download the netinst ISO, repo assets and comps
#   just build          online ISO: installs from live repositories (~1.3 GB)
#   just build-offline  offline ISO: installs with no network (~3 GB)
#   just check          validate the kickstart and its embedded shell
#   just clean          remove build output
#
# Override the target release:
#   FEDORA_RELEASE=46 just fetch-base build-offline

set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

deps:
    ./build.sh deps

check:
    ./build.sh check

fetch-base:
    ./build.sh base

packages:
    ./build.sh packages

build:
    ./build.sh online

build-offline:
    ./build.sh offline

build-all:
    ./build.sh all

clean:
    ./build.sh clean

distclean:
    ./build.sh distclean
