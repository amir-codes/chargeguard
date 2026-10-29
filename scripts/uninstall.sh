#!/bin/bash
# Removes ChargeGuard's helper and data. Restores normal charging FIRST, before anything is removed.
#
# 1. Asks the running helper to restore charging and stop enforcing (chargectl prepare-uninstall);
#    if the helper does not answer, writes the deactivate values directly (chargectl restore --direct).
# 2. Unregisters the SMAppService daemon (as the logged-in user), unloads the launchd job, removes the
#    fallback install, and restores the keys directly once more if step 1 did not go through the helper.
# 3. Restores `pmset disablesleep` if ChargeGuard left it held.
# 4. Removes /Library/Application Support/ChargeGuard and /usr/local/bin/chargectl.
# Then prints what it removed.
#
# Usage: sudo scripts/uninstall.sh [path/to/ChargeGuard.app]
#        (without a path it looks in /Applications, then in this checkout's build/ folder)
# No `set -e`: every step runs even when an earlier one fails, and failures are reported.
set -uo pipefail

LABEL="com.amir.chargeguard.helper"
SUPPORT="/Library/Application Support/ChargeGuard"
HELPER_DEST="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Uninstalling restores charging and removes a root daemon, so it needs sudo:"
    echo "  sudo $0 ${1:-}"
    exit 1
fi

# Every ChargeGuard.app we can find, the argument first.
APPS=()
for candidate in "${1:-}" "/Applications/ChargeGuard.app" "$REPO_ROOT/build/ChargeGuard.app"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then APPS+=("$candidate"); fi
done

CHARGECTL=""
chargectl_candidates=(/usr/local/bin/chargectl)
if [[ ${#APPS[@]} -gt 0 ]]; then
    for app in "${APPS[@]}"; do chargectl_candidates+=("$app/Contents/MacOS/chargectl"); done
fi
chargectl_candidates+=("$REPO_ROOT/build/chargectl")
for candidate in "${chargectl_candidates[@]}"; do
    if [[ -x "$candidate" ]]; then CHARGECTL="$candidate"; break; fi
done

# Runs a command with a time limit (macOS has no `timeout`). Returns 124 on timeout.
run_with_timeout() {
    local seconds="$1"; shift
    "$@" &
    local pid=$! waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $waited -ge $seconds ]]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        waited=$((waited + 1))
    done
    wait "$pid"
}

removed=()

echo "Step 1: restoring normal charging"
restored_via=""
if [[ -n "$CHARGECTL" ]]; then
    if run_with_timeout 30 "$CHARGECTL" prepare-uninstall; then
        restored_via="helper"
    elif "$CHARGECTL" restore --direct; then
        restored_via="direct"
    fi
fi
if [[ -z "$restored_via" ]]; then
    echo "WARNING: could not restore charging automatically (chargectl not found or failed)."
    echo "A reboot resets the charging keys to the macOS default."
fi

echo "Step 2: removing the helper daemon"
# SMAppService registrations belong to the app: unregister them as the logged-in user, inside that
# user's launchd session.
CONSOLE_USER="$(stat -f %Su /dev/console 2>/dev/null || true)"
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && ${#APPS[@]} -gt 0 ]]; then
    CONSOLE_UID="$(id -u "$CONSOLE_USER")"
    for app in "${APPS[@]}"; do
        if [[ -x "$app/Contents/MacOS/ChargeGuard" ]]; then
            if run_with_timeout 20 launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" \
                "$app/Contents/MacOS/ChargeGuard" --unregister-helper >/dev/null 2>&1; then
                removed+=("SMAppService registration of $LABEL (via $app)")
                break
            fi
        fi
    done
fi
if launchctl print "system/$LABEL" >/dev/null 2>&1; then
    if launchctl bootout "system/$LABEL" 2>/dev/null; then
        removed+=("launchd job system/$LABEL")
    else
        echo "WARNING: could not unload system/$LABEL. Remove it in System Settings > General > Login Items."
    fi
fi
if [[ -f "$PLIST" ]]; then rm -f "$PLIST" && removed+=("$PLIST"); fi
if [[ -f "$HELPER_DEST" ]]; then rm -f "$HELPER_DEST" && removed+=("$HELPER_DEST"); fi

# If the helper did not take part in step 1 it may have re-applied the limit before it stopped.
# Nothing can write the keys now, so restore them directly once more.
if [[ "$restored_via" != "helper" && -n "$CHARGECTL" && -x "$CHARGECTL" ]]; then
    echo "Restoring the keys directly now that the helper is stopped"
    if "$CHARGECTL" restore --direct; then restored_via="direct"; fi
fi

echo "Step 3: checking pmset disablesleep"
# The helper restores this itself on SIGTERM; this covers a helper that crashed while holding it.
# state.json is written by JSONEncoder: `"sleepDisabledSnapshot" : true|false`, or the key is absent.
if [[ -f "$SUPPORT/state.json" ]]; then
    previous="$(grep -oE '"sleepDisabledSnapshot"[[:space:]]*:[[:space:]]*(true|false)' "$SUPPORT/state.json" \
        | grep -oE '(true|false)$' || true)"
    if [[ "$previous" == "true" || "$previous" == "false" ]]; then
        value=0
        [[ "$previous" == "true" ]] && value=1
        if pmset -a disablesleep "$value"; then
            removed+=("pmset disablesleep hold (restored to $value)")
        fi
    fi
fi

echo "Step 4: removing data"
if [[ -d "$SUPPORT" ]]; then rm -rf "$SUPPORT" && removed+=("$SUPPORT"); fi
if [[ -f /usr/local/bin/chargectl ]]; then rm -f /usr/local/bin/chargectl && removed+=("/usr/local/bin/chargectl"); fi

echo
case "$restored_via" in
    helper) echo "Charging: restored to normal by the helper." ;;
    direct) echo "Charging: restored to normal (keys written directly)." ;;
    *)      echo "Charging: NOT confirmed restored. Reboot to reset the charging keys." ;;
esac
echo "Removed:"
if [[ ${#removed[@]} -eq 0 ]]; then
    echo "  (nothing was installed)"
else
    for item in "${removed[@]}"; do echo "  - $item"; done
fi
echo
echo "Not removed: ChargeGuard.app (drag it to the Trash), the Low Power Mode setting (left as it is),"
echo "app preferences (run as your user: defaults delete com.amir.chargeguard)."
