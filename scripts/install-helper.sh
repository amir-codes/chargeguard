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

# Captured into a variable (not piped into grep -q): with pipefail, grep -q exiting early can make
# launchctl die of SIGPIPE and turn a match into a failure.
JOB_INFO="$(launchctl print "system/$LABEL" 2>/dev/null || true)"
if [[ -n "$JOB_INFO" ]]; then
    if [[ "$JOB_INFO" == *".app/Contents/MacOS/ChargeGuardHelper"* ]]; then
        echo "The helper is already installed through the app (SMAppService, System Settings > Login Items)." >&2
        echo "Use one install path, not both: they share the label $LABEL." >&2
        echo "Remove it first with ChargeGuard > Settings > Advanced > Uninstall helper, or: sudo $(dirname "$0")/uninstall.sh" >&2
        exit 1
    fi
    echo "Stopping the running helper (it restores normal charging on SIGTERM)..."
    launchctl bootout "system/$LABEL" 2>/dev/null || true
    sleep 1
fi

# `install -d` would also re-own and re-mode an existing directory, so only create missing ones.
[[ -d /Library/PrivilegedHelperTools ]] || install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
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
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>com.amir.chargeguard</string>
	</array>
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

plutil -lint "$PLIST" >/dev/null

# enable before bootstrap: a label left disabled by an earlier `launchctl disable` cannot be bootstrapped.
launchctl enable "system/$LABEL"
launchctl bootstrap system "$PLIST"
# RunAtLoad already started it; kickstart (without -k) only starts it if it is not running.
launchctl kickstart "system/$LABEL" 2>/dev/null || true

if [[ -x "$CHARGECTL_SRC" ]]; then
    [[ -d /usr/local/bin ]] || install -d -m 755 -o root -g wheel /usr/local/bin
    install -m 755 -o root -g wheel "$CHARGECTL_SRC" /usr/local/bin/chargectl
    echo "Installed /usr/local/bin/chargectl"
fi

echo "Installed $HELPER_DEST"
echo "Installed $PLIST"
echo "The helper is running. Charge control stays off until you confirm it in ChargeGuard's first-run window."
