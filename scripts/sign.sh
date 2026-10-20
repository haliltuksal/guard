#!/bin/zsh
# build/Nöbetçi.app'i sabit kimlikle, hardened runtime ve entitlements ile imzalar.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Nöbetçi.app"
IDENT="Nöbetçi Code Signing"

if ! security find-identity -v -p codesigning | grep -q "$IDENT"; then
  echo "imza kimliği yok: '$IDENT' — önce 'make cert' çalıştır." >&2
  exit 1
fi

codesign --force --deep --options runtime --timestamp=none \
  --entitlements Resources/Nobetci.entitlements --sign "$IDENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- designated requirement ---"
codesign -d -r- "$APP" 2>&1 | grep designated || true
