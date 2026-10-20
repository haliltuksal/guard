#!/bin/zsh
# Kendinden imzalı kod imzalama sertifikası (BİR KEZ çalıştırılır).
# Amaç: sabit bir "designated requirement" — böylece uygulama yeniden derlenip
# kurulduğunda kamera/erişilebilirlik (TCC) izinleri sıfırlanmaz (D11).
#
# Bu betik kullanıcının giriş anahtar zincirine yazar ve kod imzalama için
# güven ayarlar; macOS bir kez anahtar zinciri parolası sorabilir.
# Yeniden üretilirse designated requirement değişir ve izinler sıfırlanır —
# o yüzden yalnızca bir kez.
set -euo pipefail
NAME="Nöbetçi Code Signing"
KC="$HOME/Library/Keychains/login.keychain-db"

# Not: `security` çıktısı Türkçe CN'i mojibake gösterebilir; ASCII alt dize ile eşle.
if security find-identity -v -p codesigning | grep -q "Code Signing"; then
  echo "zaten var: $NAME"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.conf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -config "$TMP/cert.conf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
# macOS'un openssl'i LibreSSL; `-legacy` yoktur. OpenSSL 3 ise eski algoritmalar için
# `-legacy` ister. Varsa kullan, yoksa kullanma — ikisi de `security import` ile uyumlu.
P12_LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then P12_LEGACY="-legacy"; fi
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:nobetci $P12_LEGACY

security import "$TMP/cert.p12" -k "$KC" -P nobetci -T /usr/bin/codesign
# Güven yalnızca kod imzalamaya ölçeklidir (-p codeSign), genel kök güveni değil.
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"

echo "oluşturuldu:"
security find-identity -v -p codesigning | grep "Code Signing" || {
  echo "UYARI: kimlik oluşturuldu ama listede bulunamadı" >&2; exit 1; }
