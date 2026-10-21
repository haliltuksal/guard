#!/bin/zsh
# `make dist`: imzalı .app'ten dağıtılabilir bir DMG üretir.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="build/Nöbetçi.app"
[ -d "$APP" ] || { echo "önce 'make app' çalıştır" >&2; exit 1; }

# Paketteki sürüm VERSION ile aynı olmalı; değilse eski bir .app paketleniyor demektir.
BUNDLED=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
[ "$BUNDLED" = "$VERSION" ] || {
  echo "sürüm uyuşmuyor: pakette $BUNDLED, VERSION $VERSION — 'make app' ile yeniden paketle" >&2
  exit 1
}

# İmza geçerli olmadan dağıtma (TCC izinleri imzaya bağlı).
codesign -v --strict "$APP" || { echo "imza geçersiz" >&2; exit 1; }

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="build/Nobetci-$VERSION.dmg"   # ASCII ad: GitHub/URL dostu (uygulama adı pakette Nöbetçi kalır)
rm -f "$DMG"
hdiutil create -volname "Nöbetçi" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "oluşturuldu: $DMG"
