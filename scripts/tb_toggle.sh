#!/bin/bash
# MiniControl Turbo Boost Control Helper
# Compatible with rugarciap's Turbo Boost Switcher DisableTurboBoost.kext
# Usage: ./tb_toggle.sh [on|off|status]

STATE_FILE="/tmp/minicontrol_tb_state"
KEXT_BUNDLE_ID="com.rugarciap.DisableTurboBoost"

# Search for DisableTurboBoost.kext across common locations
find_kext() {
    local candidate_paths=(
        "/Library/Application Support/MiniControl/DisableTurboBoost.kext"
        "/Applications/tbswitcher_resources/DisableTurboBoost.64bits.kext"
        "/Applications/tbswitcher_resources/DisableTurboBoost.kext"
        "/Library/Application Support/TurboBoostSwitcher/DisableTurboBoost.kext"
        "/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.kext"
        "/Applications/Turbo Boost Switcher Pro.app/Contents/Resources/DisableTurboBoost.kext"
        "$HOME/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.kext"
        "/Library/Extensions/DisableTurboBoost.kext"
    )

    for p in "${candidate_paths[@]}"; do
        if [ -d "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

FOUND_KEXT=$(find_kext || true)
cmd="$1"

check_status() {
    # If DisableTurboBoost kext is loaded into kernel, Turbo Boost is OFF
    if kextstat 2>/dev/null | grep -q "$KEXT_BUNDLE_ID"; then
        echo "disabled"
        return
    fi

    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "enabled"
    fi
}

set_turbo() {
    local state="$1"

    if [ "$state" = "off" ] || [ "$state" = "disable" ]; then
        # Turbo Boost OFF = Load DisableTurboBoost.kext
        if [ "$(id -u)" -eq 0 ]; then
            if [ -n "$FOUND_KEXT" ]; then
                kextload "$FOUND_KEXT" 2>/dev/null || true
            elif which voltageshift >/dev/null 2>&1; then
                voltageshift turbo 0 >/dev/null 2>&1 || true
            fi
        fi
        echo "disabled" > "$STATE_FILE"
        chmod 666 "$STATE_FILE" 2>/dev/null || true
        echo "disabled"
    else
        # Turbo Boost ON = Unload DisableTurboBoost.kext
        if [ "$(id -u)" -eq 0 ]; then
            if kextstat 2>/dev/null | grep -q "$KEXT_BUNDLE_ID"; then
                kextunload -b "$KEXT_BUNDLE_ID" 2>/dev/null || \
                ( [ -n "$FOUND_KEXT" ] && kextunload "$FOUND_KEXT" 2>/dev/null ) || true
            elif which voltageshift >/dev/null 2>&1; then
                voltageshift turbo 1 >/dev/null 2>&1 || true
            fi
        fi
        echo "enabled" > "$STATE_FILE"
        chmod 666 "$STATE_FILE" 2>/dev/null || true
        echo "enabled"
    fi
}

case "$cmd" in
    on|enable)
        set_turbo "on"
        ;;
    off|disable)
        set_turbo "off"
        ;;
    status)
        check_status
        ;;
    *)
        check_status
        ;;
esac
