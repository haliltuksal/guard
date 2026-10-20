#!/bin/zsh
# build/Nöbetçi.app'i sabit kimlikle, hardened runtime ve entitlements ile imzalar.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Nöbetçi.app"

# Kimliği SHA-1 hash ile seç (ad kodlaması/mojibake sorununu tamamen atlar).
HASH=$(security find-identity -v -p codesigning | grep "Code Signing" | head -1 | awk '{print $2}')
if [ -z "$HASH" ]; then
  echo "imza kimliği yok ('Code Signing') — önce 'make cert' çalıştır." >&2
  exit 1
fi

codesign --force --deep --options runtime --timestamp=none \
  --entitlements Resources/Nobetci.entitlements --sign "$HASH" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- designated requirement ---"
codesign -d -r- "$APP" 2>&1 | grep designated || true
