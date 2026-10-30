#!/bin/bash
# Install MiniControl Turbo Boost Privileged Helper
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Perintah ini membutuhkan hak akses root:"
    echo "  sudo make install-helper"
    exit 1
fi

DEST_DIR="/Library/Application Support/MiniControl"
HELPER_BIN="/usr/local/bin/minicontrol-tb"
SUDOERS_FILE="/etc/sudoers.d/minicontrol"

echo "==> Menyiapkan direktori $DEST_DIR..."
mkdir -p "$DEST_DIR"
mkdir -p "/usr/local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/tb_toggle.sh" "$HELPER_BIN"
chmod +x "$HELPER_BIN"

# 1. Cari kext yang sudah ada di Mac
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CANDIDATES=(
    "$SCRIPT_DIR/DisableTurboBoost.kext"
    "$PROJECT_DIR/Resources/DisableTurboBoost.kext"
    "/Applications/MiniControl.app/Contents/Resources/DisableTurboBoost.kext"
    "/Applications/tbswitcher_resources/DisableTurboBoost.64bits.kext"
    "/Applications/tbswitcher_resources/DisableTurboBoost.kext"
    "/Library/Application Support/MiniControl/DisableTurboBoost.kext"
    "/Library/Application Support/TurboBoostSwitcher/DisableTurboBoost.kext"
    "/Applications/Turbo Boost Switcher.app/Contents/Resources/DisableTurboBoost.kext"
    "/Applications/Turbo Boost Switcher Pro.app/Contents/Resources/DisableTurboBoost.kext"
    "/Library/Extensions/DisableTurboBoost.kext"
)

# Cari via Spotlight (mdfind) jika dijalankan via sudo
if [ -n "$SUDO_USER" ]; then
    SPOT_KEXT=$(sudo -u "$SUDO_USER" mdfind -name "DisableTurboBoost.kext" 2>/dev/null | head -n 1 || true)
    if [ -n "$SPOT_KEXT" ] && [ -d "$SPOT_KEXT" ]; then
        CANDIDATES=("$SPOT_KEXT" "${CANDIDATES[@]}")
    fi
fi

# Cari di /Applications secara dinamis
DYNAMIC_APP=$(find /Applications -iname "*Turbo*Boost*.app" -maxdepth 3 2>/dev/null | head -n 1 || true)
if [ -n "$DYNAMIC_APP" ]; then
    DYNAMIC_KEXT=$(find "$DYNAMIC_APP" -name "DisableTurboBoost.kext" -type d 2>/dev/null | head -n 1 || true)
    if [ -n "$DYNAMIC_KEXT" ] && [ -d "$DYNAMIC_KEXT" ]; then
        CANDIDATES=("$DYNAMIC_KEXT" "${CANDIDATES[@]}")
    fi
fi

FOUND=false
for c in "${CANDIDATES[@]}"; do
    if [ -d "$c" ]; then
        echo "==> Ditemukan driver kext di: $c"
        if [ "$c" != "$DEST_DIR/DisableTurboBoost.kext" ]; then
            cp -R "$c" "$DEST_DIR/DisableTurboBoost.kext"
        fi
        chown -R root:wheel "$DEST_DIR/DisableTurboBoost.kext"
        chmod -R 755 "$DEST_DIR/DisableTurboBoost.kext"

        # Simpan juga ke Resources project agar self-contained untuk user baru
        if [ ! -d "$PROJECT_DIR/Resources/DisableTurboBoost.kext" ]; then
            cp -R "$DEST_DIR/DisableTurboBoost.kext" "$PROJECT_DIR/Resources/DisableTurboBoost.kext"
            echo "==> Kext di-bundle ke Resources/ project untuk distribusi user baru."
        fi

        FOUND=true
        break
    fi
done

# 2. Jika pengguna belum punya driver rugarciap sama sekali:
if [ "$FOUND" = false ]; then
    echo "==> Driver kext belum terpasang. Mengunduh DisableTurboBoost.kext open-source..."
    TMP_DIR=$(mktemp -d)
    DOWNLOAD_URL="https://github.com/rugarciap/Turbo-Boost-Switcher/raw/master/DisableTurboBoost.64bit.kext.tar.gz"

    if curl -sL --max-time 15 "$DOWNLOAD_URL" -o "$TMP_DIR/kext.tar.gz" 2>/dev/null; then
        tar -xzf "$TMP_DIR/kext.tar.gz" -C "$TMP_DIR" 2>/dev/null || true
        KEXT_SOURCE=$(find "$TMP_DIR" -name "DisableTurboBoost.kext" -type d | head -n 1)
        if [ -n "$KEXT_SOURCE" ] && [ -d "$KEXT_SOURCE" ]; then
            cp -R "$KEXT_SOURCE" "$DEST_DIR/DisableTurboBoost.kext"
            chown -R root:wheel "$DEST_DIR/DisableTurboBoost.kext"
            chmod -R 755 "$DEST_DIR/DisableTurboBoost.kext"
            echo "==> Berhasil mengunduh & memasang DisableTurboBoost.kext ke $DEST_DIR"
            FOUND=true
        fi
    fi
    rm -rf "$TMP_DIR"

    if [ "$FOUND" = false ]; then
        echo "==> Perhatian: Unduhan otomatis gagal (offline). Pengguna baru dapat menyalin DisableTurboBoost.kext ke $DEST_DIR"
    fi
fi

# 3. Konfigurasi passwordless sudo untuk daemon helper
echo "==> Mengonfigurasi izin eksekusi helper..."
mkdir -p /etc/sudoers.d
echo "ALL ALL=(ALL) NOPASSWD: $HELPER_BIN" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

echo "==> Setup selesai! MiniControl siap mengontrol Turbo Boost."
