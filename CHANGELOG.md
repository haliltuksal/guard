# Değişiklik Günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.0.0/), sürümleme [SemVer](https://semver.org/lang/tr/).

## [Yayınlanmamış]

### Düzeltilenler (karanlık oda)
- **Pozlama normalleştirme:** karanlık odada, arkada parlak ekran varken yüz koyu kalıyor ve
  gündüz kaydedilmiş profille eşleşmiyordu. Kesit artık gömmeden önce sabit aydınlığa
  çekiliyor (`ExposureNormalizer`); kayıt ve çalışma anı aynı hattan geçer.
- **Uyarlanan profil:** şifreyle açtığında o anki yüzün profile eklenir (yeni ışık, gözlük,
  saç bir kez öğrenilir). Ayrı dosyada, en fazla 20 vektör; "yüz profilini yenile" sıfırlar.
- Kesit hattı sürümlendi: profil eski sürümle kaydedildiyse menüde yenileme uyarısı çıkar.

### Düzeltilenler
- **"Sahne boş sanılması" kökten çözüldü (kişi maskesi).** Yan ekrana bakmak, masada bir
  şeye uzanmak, saçını düzeltmek ya da yüzünü kaşımak yüz dedektörünü susturuyor; yakın
  mesafede gövde dedektörü de hiç tetiklenmiyor (ölçüldü: %0). Sistem sahneyi boş sanıp
  kilitliyor, sahibi fotoğraflıyor ve elin hareketini "kamera oynatıldı" okuyordu.
  Artık `VNGeneratePersonSegmentationRequest` ile sahibin bölgesinde kişi aranıyor.
  Ayrıntı: spec §19.
- Masada bir şeye uzanırken iz kutusu kayıyordu: kadrajda tek yüz varsa o yüz sahibin
  devamı sayılıyor (tanıma yerine geçmez).
- Çapa canlıyken "kamera kaydı" (T8) tetiklenmiyor.

## [0.1.2] — 2026-10-21

Tek bir kök nedenin çözümü: yüzün okunamadığı anlarda artık "masadan kalktın" sayılmıyor.

### Düzeltilenler
- **Yanlış "sahip yok" kararı kökten çözüldü (kimlik çapası).** Telefona bakmak, burun
  kaşımak ya da başı çevirmek yüzü saniyelerce okunamaz yapıyor; eski mantık bunu "masadan
  kalktı" sayıp girdi gelince ekranı kilitliyor, kullanıcının kendi yüzünü "yaklaşan yabancı"
  diye fotoğraflıyordu. Kimlik artık kare kare tanımaya değil kesintisiz **ize** bağlı
  (`OwnerAnchor`): tanıma → iz → gövdeyle taşıma. Ayrıntı: spec §18.
- **Okunamayan yüzden kimlik kararı çıkarılmıyor.** Dik açılı ya da bulanık yüz ne "sahip"
  ne "yabancı" sayılır (`FaceReadability`).
- Sürdürme eşiği yalnızca sahibin izindeki yüze uygulanıyor (yabancıya uygulanması
  0,55–0,70 arası skoru "sahip" yapardı).
- Çapa canlıyken sahibin kendi gövdesi "yüzsüz kişi" sayılmıyor ve fotoğrafı çekilmiyor.

### Eklenenler
- `nobetci-eval presence [sn]`: sahip okunmayan karelerde iz/gövde kapsaması ve poz dağılımı.

## [0.1.1] — 2026-10-21

Sen yokken kimlerin yaklaştığını görmek için fotoğraf katmanı. 119 test, derleme
uyarısı yok, `NobetciCore` satır kapsamı %95,9.

### Eklenenler
- **Yaklaşanların fotoğrafı:** sahip yokken kadrajda kişi görülünce, her kilit
  tetikleyicisinde ve yanlış şifrede şifreli JPEG (AES-GCM-256, yalnızca cihazda,
  ağ yok). Hız sınırı 3 sn/50 kare; yanlış şifre aralığı atlar.
- **Fotoğraf galerisi:** menüdeki "Fotoğraflar" düğmesi (adet rozetiyle) tüm kayıtlı
  fotoğrafları yeniden eskiye açar; ızgara, büyütme, tek tek ve toptan silme.
- **Dönüşte otomatik gösterim:** sen yokken çekilenler, yüz (ya da şifre) ile kilit
  açılır açılmaz "Buradayım" beklenmeden açılır; her fotoğraf yalnızca bir kez.
- `make relaunch`: kurup yeniden başlatır.

### Değişenler
- Fotoğraf saklama süresi varsayılanı **1 gün** (1/7/30 seçilebilir). Budama
  açılışta, nöbet başında, galeri açılışında ve ayar değiştiğinde çalışır; künyeler
  kalıcı şifreli dizinde (`photos-index.bin`), dizin kaybolursa dosya tarihiyle
  ikinci süpürme. Tavan 500 künye.
- `WindowPresenter` aynı pencereyi iki kez açmaz ve bildirim gözlemcisi biriktirmez.
- Rapor ile galerinin etiketleri tek kaynaktan (`Labels`).

### Düzeltilenler
- README ve KURULUM'da fotoğraf özelliğiyle çelişen "fotoğraf yok" ifadeleri.

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
- Bütünsel bakış: derleme uyarıları 0; kilit sayacı/durum Keychain’de (§9.1); klavye düzeni her nöbette tazelenir (§7.3); PBKDF2 turu ~250 ms’ye kalibre (§9.2); kilit açma penceresine yalnızca T_kabul üstü kareler (§5.4.1).
