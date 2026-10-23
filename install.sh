#!/bin/bash
# Nöbetçi kurulumu — tek komut:
#
#   curl -fsSL https://raw.githubusercontent.com/haliltuksal/guard/main/install.sh | bash
#
# Neden var: Nöbetçi Apple'ın noter onayından (notarization) geçmiyor; bunun için ücretli
# bir Apple Developer ID gerekir. Tarayıcıyla indirilen uygulamaya macOS "karantina"
# işareti koyar ve ilk açılışta noter bileti arar; bilet olmayınca "Nöbetçi Açılmadı"
# penceresini gösterir (macOS 15+ bu pencerede "Aç" düğmesi de sunmaz).
#
# curl ile indirilen dosyaya bu işaret konmaz. Betik, Apple'ın yerine bütünlüğü kendisi
# doğrular: indirilen disk görüntüsünün SHA-256 özetini ve uygulamanın kod imzasını.
# Doğrulama tutmazsa hiçbir şey kurmaz.
#
# Seçenekler (ortam değişkeni):
#   NOBETCI_APP_DIR=…     kurulum klasörü (varsayılan /Applications)
#   NOBETCI_BASE_URL=…    indirme adresi (varsayılan: en son sürüm)
#   NOBETCI_NO_LAUNCH=1   kurduktan sonra uygulamayı açma

set -euo pipefail

REPO="haliltuksal/guard"
DMG_NAME="Nobetci.dmg"

say()  { printf '%s\n' "$*"; }
fail() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

check_platform() {
    # hw.optional.arm64: Rosetta altında çalışan bir kabukta da Apple Silicon'u doğru söyler
    # (uname -m orada x86_64 döner).
    [ "$(sysctl -in hw.optional.arm64 2>/dev/null)" = "1" ] \
        || fail "Nöbetçi Apple Silicon (M1 ve sonrası) gerektirir; bu Mac Intel işlemcili."
    local version major
    version="$(sw_vers -productVersion)"
    major="${version%%.*}"
    case "$major" in ''|*[!0-9]*) fail "macOS sürümü okunamadı: $version" ;; esac
    [ "$major" -ge 14 ] || fail "macOS 14 Sonoma veya üstü gerekir (bu Mac: $version)."
}

main() {
    local base_url app_dir work mount src dest version
    base_url="${NOBETCI_BASE_URL:-https://github.com/$REPO/releases/latest/download}"
    app_dir="${NOBETCI_APP_DIR:-/Applications}"

    check_platform

    work="$(mktemp -d)"
    mount="$work/mnt"
    # shellcheck disable=SC2064  # yollar şimdi sabitlenmeli
    trap "hdiutil detach '$mount' -quiet >/dev/null 2>&1 || true; rm -rf '$work'" EXIT

    say "Nöbetçi indiriliyor…"
    # Yönlendirmeler yalnızca https'e: GitHub indirme bağlantısı CDN'e yönlendirir.
    curl -fsSL --proto-redir '=https' -o "$work/$DMG_NAME" "$base_url/$DMG_NAME" \
        || fail "İndirilemedi: $base_url/$DMG_NAME"
    curl -fsSL --proto-redir '=https' -o "$work/$DMG_NAME.sha256" "$base_url/$DMG_NAME.sha256" \
        || fail "Özet dosyası indirilemedi: $base_url/$DMG_NAME.sha256"

    ( cd "$work" && shasum -a 256 -c "$DMG_NAME.sha256" >/dev/null 2>&1 ) \
        || fail "SHA-256 özeti tutmuyor — dosya bozuk ya da değiştirilmiş. Hiçbir şey kurulmadı."
    say "✓ SHA-256 özeti doğrulandı"

    mkdir -p "$mount"
    hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mount" "$work/$DMG_NAME" >/dev/null \
        || fail "Disk görüntüsü açılamadı."
    src=""
    for candidate in "$mount"/*.app; do
        [ -d "$candidate" ] && src="$candidate"
    done
    [ -n "$src" ] || fail "Disk görüntüsünde uygulama bulunamadı."
    codesign --verify --deep --strict "$src" 2>/dev/null \
        || fail "Uygulamanın kod imzası geçersiz. Hiçbir şey kurulmadı."
    say "✓ Kod imzası doğrulandı"

    if [ ! -w "$app_dir" ]; then
        say "Not: $app_dir klasörüne yazma izni yok; $HOME/Applications içine kuruluyor."
        app_dir="$HOME/Applications"
        mkdir -p "$app_dir"
    fi
    dest="$app_dir/$(basename "$src")"
    rm -rf "$dest"
    ditto "$src" "$dest"
    # Karantina işaretini kaldır: betiği bilerek çalıştırdın ve bütünlük yukarıda doğrulandı.
    # (Daha önce tarayıcıdan indirilip kopyalanmış eski bir sürüm de böylece temizlenir.)
    xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    codesign --verify --deep --strict "$dest" 2>/dev/null \
        || fail "Kurulan kopyanın imzası doğrulanamadı."
    version="$(defaults read "$dest/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?')"
    say "✓ Kuruldu: $dest (sürüm $version)"

    # Eski sürüm çalışıyorsa kapat: launchd yeniden başlatırsa artık yeni sürüm açılır.
    # Yalnızca varsayılan kurulumda — özel klasöre (deneme) kurarken çalışan uygulamaya dokunma.
    if [ -z "${NOBETCI_APP_DIR:-}" ] && pgrep -x Nobetci >/dev/null 2>&1; then
        say "Çalışan eski sürüm kapatılıyor…"
        pkill -x Nobetci 2>/dev/null || true
        sleep 1
    fi

    if [ "${NOBETCI_NO_LAUNCH:-0}" != "1" ]; then
        open "$dest"
        say "Nöbetçi açıldı. Menü çubuğundaki kalkan simgesinden kurulumu tamamla."
    fi
}

# Betiğin tamamı indirilmeden hiçbir satır çalışmasın (curl | bash yarıda kesilirse).
main "$@"
