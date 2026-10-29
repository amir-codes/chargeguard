#!/bin/bash
# Removes ChargeGuard's helper and data. Restores normal charging FIRST.
#
# 1. Asks the running helper to restore charging and stop enforcing (chargectl prepare-uninstall);
#    if the helper is not running, writes the deactivate values directly (chargectl restore --direct).
# 2. Unloads and removes the daemon (fallback install) and unregisters the SMAppService daemon.
# 3. Restores `pmset disablesleep` if ChargeGuard left it set.
# 4. Removes /Library/Application Support/ChargeGuard and /usr/local/bin/chargectl.
#
# Usage: sudo scripts/uninstall.sh [path/to/ChargeGuard.app]
set -uo pipefail

LABEL="com.amir.chargeguard.helper"
APP="${1:-/Applications/ChargeGuard.app}"
SUPPORT="/Library/Application Support/ChargeGuard"
HELPER_DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Uninstalling restores charging and removes a root daemon, so it needs sudo:"
    echo "  sudo $0 $APP"
    exit 1
fi

removed=()

CHARGECTL=""
for candidate in /usr/local/bin/chargectl "$APP/Contents/MacOS/chargectl" "$REPO_ROOT/build/chargectl"; do
    if [[ -x "$candidate" ]]; then CHARGECTL="$candidate"; break; fi
done

echo "Step 1: restoring normal charging"
restored=0
if [[ -n "$CHARGECTL" ]]; then
    if "$CHARGECTL" prepare-uninstall; then
        restored=1
    elif "$CHARGECTL" restore --direct; then
        restored=1
    fi
fi
if [[ $restored -eq 0 ]]; then
    echo "WARNING: could not restore charging automatically (chargectl not found or failed)."
    echo "A reboot resets every charging key to the macOS default."
fi

echo "Step 2: removing the helper daemon"
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "system/$LABEL" 2>/dev/null && removed+=("launchd job system/$LABEL")
fi
if [[ -f "$PLIST" ]]; then rm -f "$PLIST" && removed+=("$PLIST"); fi
if [[ -f "$HELPER_DEST" ]]; then rm -f "$HELPER_DEST" && removed+=("$HELPER_DEST"); fi

# SMAppService registrations belong to the app: ask it to unregister as the console user.
CONSOLE_USER="$(stat -f %Su /dev/console)"
if [[ -x "$APP/Contents/MacOS/ChargeGuard" && -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
    if sudo -u "$CONSOLE_USER" "$APP/Contents/MacOS/ChargeGuard" --unregister-helper >/dev/null 2>&1; then
        removed+=("SMAppService registration of $LABEL")
    fi
fi

echo "Step 3: checking pmset disablesleep"
if [[ -f "$SUPPORT/state.json" ]] && grep -q '"sleepDisabledSnapshot"' "$SUPPORT/state.json"; then
    previous="$(grep -o '"sleepDisabledSnapshot" : [a-z]*' "$SUPPORT/state.json" | awk '{print $3}')"
    value=0
    [[ "$previous" == "true" ]] && value=1
    pmset -a disablesleep "$value" && removed+=("pmset disablesleep hold (restored to $value)")
fi

echo "Step 4: removing data"
if [[ -d "$SUPPORT" ]]; then rm -rf "$SUPPORT" && removed+=("$SUPPORT"); fi
if [[ -f /usr/local/bin/chargectl ]]; then rm -f /usr/local/bin/chargectl && removed+=("/usr/local/bin/chargectl"); fi

echo
echo "Removed:"
if [[ ${#removed[@]} -eq 0 ]]; then
    echo "  (nothing was installed)"
else
    for item in "${removed[@]}"; do echo "  - $item"; done
fi
echo
echo "Not removed: $APP (drag it to the Trash), Low Power Mode setting (left as it is),"
echo "app preferences (defaults delete com.amir.chargeguard)."
