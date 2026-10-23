# Nöbetçi — Kurulum

## En kolay yol: tek komut

Terminal'i aç (⌘Space → "Terminal") ve yapıştır:

```bash
curl -fsSL https://raw.githubusercontent.com/haliltuksal/guard/main/install.sh | bash
```

İndirir, SHA-256 özetini ve kod imzasını doğrular, kurar ve açar. "Açılmadı" penceresi çıkmaz.

## DMG ile

1. `Nobetci.dmg` dosyasını aç, **Nöbetçi**'yi **Applications** klasörüne sürükle.
2. Nöbetçi'yi aç. macOS **"Nöbetçi Açılmadı"** der ve yalnızca *Çöp Sepeti'ne Taşı* /
   *Bitti* sunar — **Bitti**'ye bas. (Uygulama Apple'ın noter onayından geçmediği için;
   macOS 15'ten beri bu pencerede "Aç" düğmesi yok.)
3. **Sistem Ayarları → Gizlilik ve Güvenlik** → en alta kaydır → "Nöbetçi … engellendi"
   satırının yanındaki **Yine de Aç** → parolanı gir.
4. Nöbetçi'yi tekrar aç → çıkan pencerede **Yine de Aç**.

Kısa yol: Terminal'de `xattr -dr com.apple.quarantine /Applications/Nöbetçi.app`

## İlk açılış

1. Kurulum sihirbazı açılır:
   - **İzinler:** Kamera, Erişilebilirlik ve Bildirimler izni ver. Her birinin
     neden gerektiği tek cümleyle yazılıdır.
   - **Şifre:** En az 6 karakter bir uygulama şifresi belirle (yüz tanınmazsa
     bununla açarsın).
   - **Yüz kaydı:** Başını yavaşça çevirerek yüzünü kaydet.
2. Artık menü çubuğundaki kalkan simgesinden **"Uzaktayım"** diyebilirsin
   (ya da ⌃⌥⌘L).

## Kaldırma

Menü çubuğu → **Ayarlar → Hakkında → "Nöbetçi'yi kaldır"**. Yüz profili, şifre
ve tüm ayarlar silinir.

## Notlar

- Hiçbir veri cihazından çıkmaz; uygulamanın internet bağlantısı yoktur. Sen yokken yaklaşanların fotoğrafı şifreli olarak bu Mac'te saklanır ve 1 gün sonra silinir; menüdeki **Fotoğraflar** düğmesinden görürsün (Ayarlar → Fotoğraflar'dan kapatılabilir).
- MacBook kamerasında iPhone'daki gibi derinlik sensörü yoktur; bu bir gizlilik
  kalkanıdır, macOS kilit ekranının birebir yerini tutmaz.
