#!/bin/bash
# Packs ChargeGuard.app into a compressed disk image with an Applications shortcut.
# Usage: scripts/make-dmg.sh build/ChargeGuard.app build/ChargeGuard.dmg
set -euo pipefail

APP="${1:?path to ChargeGuard.app}"
DMG="${2:?output .dmg path}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/ChargeGuard.app"
ln -s /Applications "$STAGING/Applications"
cp "$REPO_ROOT/README.md" "$STAGING/README.md"
cp "$REPO_ROOT/docs/SAFETY.md" "$STAGING/SAFETY.md"

rm -f "$DMG"
hdiutil create -volname "ChargeGuard" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Created $DMG"
