#!/bin/bash
# Installs the latest ChargeGuard release:
#
#   curl -fsSL https://raw.githubusercontent.com/amir-codes/chargeguard/main/scripts/install.sh | bash
#
# It downloads ChargeGuard.dmg and its checksum from the GitHub release, checks both the checksum and the
# app's signature, copies ChargeGuard.app to /Applications and opens it. Files downloaded with curl don't
# get macOS's quarantine flag, so the app opens without the "Open Anyway" step a browser download needs.
# Nothing here uses sudo: the root helper is installed later from the app's first-run window, which
# explains what it does and asks first.
#
# Options, as environment variables in front of `bash`:
#   CHARGEGUARD_VERSION=v1.0.0      install that release instead of the latest
#   CHARGEGUARD_DIR=~/Applications  install somewhere other than /Applications
#   CHARGEGUARD_OPEN=0              don't open the app afterwards
set -euo pipefail

REPO="amir-codes/chargeguard"

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Everything runs from main, so a partly downloaded script does nothing.
main() {
    [[ "$(uname -s)" == "Darwin" ]] || fail "ChargeGuard is a macOS app."
    [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]] || fail "ChargeGuard needs a Mac with Apple silicon."
    local os major
    os="$(sw_vers -productVersion)"
    major="${os%%.*}"
    (( major >= 14 )) || fail "ChargeGuard needs macOS 14 or later; this Mac has macOS $os."

    local base
    if [[ -n "${CHARGEGUARD_VERSION:-}" ]]; then
        base="https://github.com/$REPO/releases/download/$CHARGEGUARD_VERSION"
    else
        base="https://github.com/$REPO/releases/latest/download"
    fi

    local dir="${CHARGEGUARD_DIR:-/Applications}"
    dir="${dir%/}"
    [[ -n "$dir" ]] || fail "CHARGEGUARD_DIR is empty."
    mkdir -p "$dir" 2>/dev/null || true
    [[ -d "$dir" && -w "$dir" ]] || fail "Can't write to $dir. Use an administrator account, or set CHARGEGUARD_DIR=~/Applications."

    if pgrep -xq ChargeGuard; then
        fail "ChargeGuard is running. Quit it from its menu bar pop-up, then run this again."
    fi

    TMP="$(mktemp -d)"
    MOUNT="$TMP/mount"
    trap cleanup EXIT

    say "Downloading ChargeGuard from github.com/$REPO …"
    curl -fL --progress-bar -o "$TMP/ChargeGuard.dmg" "$base/ChargeGuard.dmg" \
        || fail "Download failed: $base/ChargeGuard.dmg. Is there a published release yet?"
    curl -fsSL -o "$TMP/ChargeGuard.dmg.sha256" "$base/ChargeGuard.dmg.sha256" \
        || fail "Couldn't download the checksum: $base/ChargeGuard.dmg.sha256"
    (cd "$TMP" && shasum -a 256 -c ChargeGuard.dmg.sha256 >/dev/null 2>&1) \
        || fail "The download doesn't match its checksum. Nothing was installed; try again."
    say "Checksum OK."

    mkdir -p "$MOUNT"
    hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$TMP/ChargeGuard.dmg" >/dev/null \
        || fail "Couldn't open the disk image."
    ATTACHED=1
    [[ -d "$MOUNT/ChargeGuard.app" ]] || fail "ChargeGuard.app is missing from the disk image."
    codesign --verify --deep --strict "$MOUNT/ChargeGuard.app" 2>/dev/null \
        || fail "ChargeGuard.app's signature is invalid. Nothing was installed."

    # Copy next to the target first, so a failed copy never leaves a half-installed app behind.
    local target="$dir/ChargeGuard.app"
    local staging="$dir/.ChargeGuard.app.installing"
    rm -rf "$staging"
    ditto "$MOUNT/ChargeGuard.app" "$staging"
    rm -rf "$target"
    mv "$staging" "$target"

    local version
    version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$target/Contents/Info.plist" 2>/dev/null || echo "?")"
    say "Installed ChargeGuard $version in $dir."

    if [[ "${CHARGEGUARD_OPEN:-1}" != "0" ]]; then
        open "$target"
        say "Opening it now. The first-run window explains the helper and asks before it changes anything."
    fi
}

cleanup() {
    if [[ "${ATTACHED:-0}" == "1" ]]; then
        hdiutil detach -quiet "$MOUNT" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT" 2>/dev/null || true
    fi
    if [[ -n "${TMP:-}" ]]; then
        rm -rf "$TMP"
    fi
}

main "$@"
