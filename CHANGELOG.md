# Değişiklik Günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.0.0/), sürümleme [SemVer](https://semver.org/lang/tr/).

## [0.1.0] — 2026-10-21

İlk sürüm. Çekirdek mantık, yüz modeli ve tüm katmanlar hazır; cihaz üzerinde
doğrulama (izinler, görsel kontroller, imza) bekliyor — bkz `docs/test-report.md`.

### Eklenenler
- Koruma durum makinesi (off → preparing → guarding(present/absent) → locked) ve
  14 tetikleyici (yabancı yüz, yüzsüz kişi, girdi, kapak açısı, hareket, kamera
  örtülme/kesilme/kayma, ekran, USB, güç, uyku, yeniden başlatma, filtre kaybı).
- Yüz tanıma: FaceNet → Core ML (Neural Engine, ~0,9 ms), 5 nokta hizalama,
  kosinüs eşleştirme + histerezis, göz kırpma canlılık kontrolü, sıkı mod.
- Yalnızca yüz + uygulama şifresiyle kilit açma; katlanan bekleme süresi; PBKDF2.
- Çok ekranlı kalkan, en alt seviye girdi filtresi, kiosk kilitleri, uyku engelleme
  (sahte girdi olmadan — yalnızca güç bildirimleri).
- Şifreli yerel depolama (AES-GCM) ve imzalı ayarlar (HMAC); launchd ile çökme sonrası
  kilitli yeniden başlatma.
- Türkçe menü çubuğu arayüzü, kurulum sihirbazı, ayarlar, "Sen yokken olanlar" raporu.

### Bilinçli olarak dışarıda
- Fotoğraf çekme.
- "Aktif görünme" (Slack/Teams boşta kalma sayaçlarını sahte girdiyle sıfırlama).

### Değişenler (2026-10-21)
- Dönüş davranışı varsayılanı "nöbet sürsün" (kullanıcı kararı); menüde "Buradayım".
- T1 zamanlaması iz başına (0,5 sn kabul / 3 kare T_red altı); T6 ≥0,5 sn süreklilik.
- Göz kırpma (canlılık) varsayılan kapalı, isteğe bağlı (kullanıcı kararı); kilit açma kayan pencere (1 sn/≥5); eski settings.json yeni anahtarlarla uyumlu.
