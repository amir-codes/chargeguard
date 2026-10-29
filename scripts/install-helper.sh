#!/bin/bash
# Fallback installer for the ChargeGuard helper daemon (the primary path is SMAppService from the app).
# Copies the helper to /Library/PrivilegedHelperTools, writes /Library/LaunchDaemons/<label>.plist,
# bootstraps it into the system domain, and installs chargectl to /usr/local/bin.
#
# Usage: sudo scripts/install-helper.sh [path/to/ChargeGuard.app]
set -euo pipefail

LABEL="com.amir.chargeguard.helper"
APP="${1:-}"
if [[ -z "$APP" ]]; then
    for candidate in "/Applications/ChargeGuard.app" "$(cd "$(dirname "$0")/.." && pwd)/build/ChargeGuard.app"; do
        if [[ -d "$candidate" ]]; then APP="$candidate"; break; fi
    done
fi

if [[ $EUID -ne 0 ]]; then
    echo "This installs a root daemon and needs sudo:"
    echo "  sudo $0 ${APP:-path/to/ChargeGuard.app}"
    exit 1
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "ChargeGuard.app not found. Pass its path: sudo $0 /path/to/ChargeGuard.app" >&2
    exit 1
fi

HELPER_SRC="$APP/Contents/MacOS/ChargeGuardHelper"
CHARGECTL_SRC="$APP/Contents/MacOS/chargectl"
HELPER_DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [[ ! -x "$HELPER_SRC" ]]; then
    echo "Helper binary missing: $HELPER_SRC" >&2
    exit 1
fi

if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    echo "Stopping the running helper (it restores normal charging on SIGTERM)..."
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    sleep 1
fi

install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
install -m 755 -o root -g wheel "$HELPER_SRC" "$HELPER_DEST"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$HELPER_DEST</string>
	</array>
	<key>MachServices</key>
	<dict>
		<key>$LABEL</key>
		<true/>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Adaptive</string>
</dict>
</plist>
PLIST_EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST"
launchctl enable "system/$LABEL"
launchctl kickstart -k "system/$LABEL"

if [[ -x "$CHARGECTL_SRC" ]]; then
    install -d -m 755 /usr/local/bin
    install -m 755 "$CHARGECTL_SRC" /usr/local/bin/chargectl
    echo "Installed /usr/local/bin/chargectl"
fi

echo "Installed $HELPER_DEST"
echo "Installed $PLIST"
echo "The helper is running. Charge control stays off until you confirm it in ChargeGuard's first-run window."
