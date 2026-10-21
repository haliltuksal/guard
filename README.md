# Nöbetçi

Masandan kalktığında Mac'ini **uyanık tutan**, başına **yabancı biri geçince ekranı anında bulanıklaştırıp klavye-fareyi kapatan**, sen geri gelip **yüzün tanınınca açılan** menü çubuğu uygulaması.

- 🔒 Yabancı yüz, yaklaşan kişi, kapak oynatma, Mac'i kaldırma, kamerayı kapatma, USB/ekran takma → **ekran bulanır, girdi kapanır**
- 👤 Sadece **senin yüzün** (ya da uygulama şifren) açar
- 🔋 Nöbet boyunca Mac **uyumaz**, ekran koruyucu devreye girmez
- 📸 Sen yokken yaklaşanların **fotoğrafını çeker** — şifreli, yalnızca bu Mac'te; döndüğünde kimin geldiğini görürsün
- 🕵️ **Hiçbir veri cihazından çıkmaz** — uygulamanın internet bağlantısı yoktur
- 🧠 Yüz tanıma tamamen cihazda (Apple Neural Engine, ~1 ms)

> **Gereksinimler:** Apple Silicon Mac (M1 ve sonrası), macOS 14 Sonoma veya üstü, dahili kamera.

---

## Kurulum (3 dakika)

1. **[Releases](https://github.com/haliltuksal/guard/releases)** sayfasından en son `Nobetci-x.y.z.dmg` dosyasını indir.
2. DMG'yi aç, **Nöbetçi**'yi **Applications** klasörüne sürükle.
3. Nöbetçi'yi aç. macOS **"geliştirici doğrulanamadı"** diyecek — bu normal (App Store dışı, Apple tarafından notarize edilmemiş sürüm):
   **Sistem Ayarları → Gizlilik ve Güvenlik** → aşağıda *"Nöbetçi engellendi"* satırının yanındaki **"Yine de Aç"**.
4. Açılan **kurulum sihirbazı**nda:
   - **İzinler:** Kamera, Erişilebilirlik ve Bildirimler — çıkan pencerelerde izin ver.
     (Erişilebilirlik iznini verdikten sonra uygulamayı bir kez kapatıp açman gerekebilir.)
   - **Şifre:** En az 6 karakter. Yüzün tanınmazsa bununla açarsın.
   - **Yüz kaydı:** Kameraya bak, başını yavaşça çevir (50 kare toplanır, ~10 sn).

Bitti. Menü çubuğunda bir **kalkan simgesi** göreceksin.

## Kullanım

| Yapacağın | Nasıl |
|---|---|
| Masadan kalkarken | Kalkan simgesi → **Uzaktayım** (ya da **⌃⌥⌘L**) |
| Geri döndüğünde | Kameraya bak → kilit **kendiliğinden** açılır; nöbet sürer |
| Nöbeti bitirmek | Kalkan simgesi → **Buradayım** |
| Yüz tanınmazsa | Kilit ekranında şifreni yaz, Return |
| Sen yokken ne oldu? | "Buradayım" dediğinde olay listesi **ve çekilen fotoğraflar** açılır |

Nöbetteyken menüde **kamera · kapak · hareket · uyanık** göstergeleri yanar.

## Sık sorulanlar

**Şifremi unuttum, yüzüm de tanınmıyor.** Güç tuşuna basılı tutup Mac'i kapat; açılışta macOS şifrenle gir. Nöbetçi kapalı başlar; Ayarlar → Kilit açma'dan şifreni yenile.

**Loş odada yanlış alarm veriyor.** Ayarlar → Algılama'dan hassasiyetleri düşür. Kamera kapağını/çıkartmayı kapatmak kasıtlı olarak kilit sebebidir.

**Karşımdayken kilitlendi.** Ayarlar → Kilit açma → **Yüz profilini yenile** (farklı ışıkta, gözlüklü/gözlüksüz bir tur daha).

**Daha sıkı güvenlik istiyorum.** Ayarlar → Kilit açma → *Göz kırpma iste* (fotoğrafla kandırmayı zorlaştırır) ve *Sıkı mod* (baş hareketi ister).

**Kaldırmak.** Ayarlar → Hakkında → **Nöbetçi'yi kaldır** — yüz profili, şifre ve tüm veriler silinir.

## Gizlilik

- Yüzünün **fotoğrafı değil**, sadece sayısal özellikleri saklanır; AES-GCM ile şifreli, anahtar Keychain'de, iCloud'a gitmez.
- Sen yokken çekilen fotoğraflar AES-GCM ile **şifrelenir**, yalnızca bu Mac'te kalır ve saklama süresi dolunca silinir (varsayılan 30 gün). Ayarlar → Fotoğraflar'dan kapatabilir ya da hepsini silebilirsin.
- Yabancıların yüz verisi tanıma için **saklanmaz**.
- Uygulamada **ağ kodu yok**.
- Kilit ekranında "Kamera etkin" yazar; yaklaşan kişi kameranın açık olduğunu görür.

Dürüst bir sınır: MacBook kamerasında iPhone'daki gibi derinlik sensörü yoktur. Bu bir **gizlilik kalkanıdır**, macOS kilit ekranının birebir yerini tutmaz.

---

## Geliştiriciler için

Xcode gerekmez; Command Line Tools + Swift 6 yeter. Yüz modeli için Python 3.12 + [uv](https://github.com/astral-sh/uv).

```bash
git clone https://github.com/haliltuksal/guard.git && cd guard
make model      # FaceNet → Core ML (bir kez; ~1 dk, internet gerekir)
make test       # 97 test (Swift Testing)
make coverage   # NobetciCore ≥ %90 kapısı
make cert       # kendinden imzalı kod imzalama kimliği (bir kez)
make install    # /Applications/Nöbetçi.app
make dist       # Nobetci-<sürüm>.dmg
swift run nobetci-eval live 10   # kamera ile tanıma/eşik tanılaması
```

| Katman | Sorumluluk |
|---|---|
| `NobetciCore` | Saf durum makinesi ve tüm kararlar — donanıma dokunmaz, tam test edilir |
| `NobetciVision` | Kamera karesi → `FrameSummary` (Apple Vision + Core ML yüz tanıma) |
| `NobetciSystem` | macOS adaptörleri: sensörler, girdi filtresi, kalkan, güç, launchd, Keychain |
| `Nobetci` | SwiftUI arayüz + parçaları bağlayan `AppModel` |

Tasarım: `docs/superpowers/specs/` · Plan: `docs/superpowers/plans/` · Model: `docs/model-evaluation.md` · Doğrulama: `docs/test-report.md`

İlkeler: üçüncü parti çalışma zamanı bağımlılığı yok · ağ yok · fotoğraf yalnızca cihazda ve şifreli · sahte etkinlik yok · emin olunamayan her durumda kilitle.

**Lisans:** Kod [MIT](LICENSE). Yüz modeli ağırlıkları (VGGFace2 üzerinde eğitilmiş FaceNet) ayrıca ticari olmayan kullanım koşuluna tabidir; `make model` bunları ayrıca indirir, depoda yer almaz.
