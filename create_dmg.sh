#!/bin/bash
set -euo pipefail

# Script untuk membuat Apple Disk Image (.dmg) resmi untuk MacVolumeMixer
# Dilengkapi symlink /Applications agar pengguna cukup drag-and-drop untuk install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MacVolumeMixer"
SOURCE_APP="/Applications/$APP_NAME.app"
VERSION="v0.4.0-beta"
VOL_NAME="Mac Volume Mixer $VERSION"
DMG_NAME="MacVolumeMixer-$VERSION.dmg"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="$SCRIPT_DIR/.dmg_staging"

if [ ! -d "$SOURCE_APP" ]; then
    echo "⚠️  Aplikasi tidak ditemukan di $SOURCE_APP. Menjalankan bundle_app.sh terlebih dahulu..."
    "$SCRIPT_DIR/bundle_app.sh"
fi

echo "📦 Mempersiapkan staging folder untuk DMG..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

# Salin aplikasi ke staging
cp -R "$SOURCE_APP" "$STAGING_DIR/$APP_NAME.app"

# Buat symlink Applications untuk drag-and-drop install khas macOS
ln -s /Applications "$STAGING_DIR/Applications"

# Buat Disk Image (.dmg) terkompresi menggunakan hdiutil bawaan macOS
OUTPUT_DMG="$DIST_DIR/$DMG_NAME"
TEMP_DMG="$SCRIPT_DIR/.temp.dmg"
rm -f "$TEMP_DMG" "$OUTPUT_DMG"

echo "💿 Membuat Disk Image DMG..."
hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOL_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG"

echo "🗜️  Mengompres DMG dengan format UDZO (read-only compressed)..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"

# Bersihkan temporary files
rm -rf "$STAGING_DIR" "$TEMP_DMG"

echo "✅ DMG Berhasil Dibuat!"
echo "📁 Lokasi: $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
shasum -a 256 "$OUTPUT_DMG"
