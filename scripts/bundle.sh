#!/bin/zsh
# Release derlemesini .app paketine dönüştürür. İmzalama scripts/sign.sh'de.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
APP="build/Nöbetçi.app"

swift build -c release --product Nobetci
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Nobetci" "$APP/Contents/MacOS/Nobetci"

# SwiftPM kaynak paketi (Localizable.strings vb.) varsa kopyala.
if [ -d "$BIN/Nobetci_Nobetci.bundle" ]; then
  cp -R "$BIN/Nobetci_Nobetci.bundle" "$APP/Contents/Resources/"
fi

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

[ -f build/Nobetci.icns ] && cp build/Nobetci.icns "$APP/Contents/Resources/Nobetci.icns"
[ -d build/Model.mlmodelc ] && cp -R build/Model.mlmodelc "$APP/Contents/Resources/"
if [ -d Resources/LaunchAgents ]; then
  cp Resources/LaunchAgents/*.plist "$APP/Contents/Resources/" 2>/dev/null || true
fi

echo "built $APP (sürüm $VERSION)"
