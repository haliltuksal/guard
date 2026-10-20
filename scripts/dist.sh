#!/bin/zsh
# `make dist`: imzalı .app'ten dağıtılabilir bir DMG üretir.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="build/Nöbetçi.app"
[ -d "$APP" ] || { echo "önce 'make app' çalıştır" >&2; exit 1; }

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="build/Nöbetçi-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Nöbetçi" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "oluşturuldu: $DMG"
