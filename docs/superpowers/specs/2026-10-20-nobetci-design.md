# Nöbetçi — Tasarım Dokümanı

| | |
|---|---|
| Tarih | 2026-10-20 |
| Durum | Kullanıcı incelemesinde |
| Sahip | Halil Tuksal |
| Hedef sürüm | 1.0 |

> Bu doküman, 20 Ekim 2026 tarihli tasarım görüşmesinde bölüm bölüm onaylanan kararları tek yerde toplar.
> Her teknik iddia ya **doğrulandı** (kanıtıyla, §15.1) ya da **doğrulanacak** (testi ve yedek planıyla, §15.2) olarak işaretlidir.
> Varsayıma dayanan karar yoktur. Kalite çıtası (kullanıcı): *"En profesyoneli ne olacaksa o; maliyetten kısma; zannederek iş yapma; testlerini yap."*

---

## 1. Amaç

### 1.1 Problem
Kullanıcı bilgisayardan kısa süreliğine kalkarken iki şeyi aynı anda istiyor:

1. Mac uyumasın ve otomatik kilitlenmesin; döndüğünde ekran açık ve çalışır durumda olsun (caffeinate benzeri uyku engelleme).
2. Bu sürede ekranı başkası görmesin, bilgisayarı başkası kullanamasın.

macOS'un kendi kilidi ikinciyi çözer ama birinciyi bozar. Uyku engelleyiciler birinciyi çözer ama ikinciyi bozar.

### 1.2 Çözüm özeti
Nöbetçi, menü çubuğunda çalışan bir macOS uygulamasıdır. Kullanıcı kalkarken "Uzaktayım" der (menüden ya da ⌃⌥⌘L ile). Nöbet süresince:

- Mac uyanık tutulur; ekran koruyucu ve otomatik kilit devreye girmez.
- Dahili kamera, kapak açısı sensörü, ivmeölçer, girdi olayları ve fiziksel bağlantılar izlenir.
- Sahibin dışında biri görünür ya da herhangi bir müdahale olursa tüm ekranlar anında bulanıklaşır, tüm girdiler kapanır.
- Kilit yalnızca **sahibin yüzü (canlılık kontrolüyle)** ya da **uygulamaya özel şifre** ile açılır.
- Sahip döndüğünde "Sen yokken olanlar" raporu gösterilir.

### 1.3 Hedef kullanıcılar
Kendi Mac'ini korumak isteyen bireysel kullanıcılar. Uygulama DMG olarak dağıtılır; App Store ve notarization yoktur. Arayüz Türkçedir.

### 1.4 Başarı ölçütleri
1. Sahip yokken biri gelirse ekran **1 sn'den kısa sürede** okunamaz hale gelir ve **hiçbir girdi hiçbir uygulamaya ulaşmaz** (tetikleyici bazında hedefler §5.3).
2. Sahip döndüğünde kilit şifresiz, ortanca **≤ 1,5 sn** içinde açılır.
3. Sahip, yanlış alarmda ya da tanınmadığında **asla bilgisayarına kilitli kalmaz** (şifre ve kurtarma yolu, §3.5).
4. Nöbet boyunca Mac uyumaz, ekran koruyucu ve otomatik kilit devreye girmez (≥ 15 dk kabul testi).
5. Hiçbir veri cihazdan çıkmaz (ağ kodu yoktur; testle doğrulanır).
6. Tüm kabul testleri (§13.4) geçer ve sonuçları ölçümleriyle birlikte `docs/test-report.md` dosyasında kayıtlıdır.

### 1.5 Kapsam dışı (v1)
- Siri ve Sesli Denetim ile sesli komutlar (kurulumda tespit edilip uyarı verilir, §9.4)
- Uzaktan erişim (SSH, açık bırakılmış ekran paylaşımı) ve Mac'te önceden çalışan kötü amaçlı yazılım
- Özel hazırlanmış saldırılar: 3B maske, canlı deepfake
- Gerçek macOS kilit ekranına geçiş (kullanıcı kararı)
- Korumadan bağımsız "yalnızca uyanık tut" modu (kullanıcı kararı)
- **Sahte etkinlik ("aktif görünme"):** Slack/Teams gibi araçların okuduğu boşta kalma sayaçlarını sentetik klavye/fare olaylarıyla sıfırlamak. Kullanıcı gerçekte uzaktayken başkalarına masasındaymış izlenimi verdiği için **bilinçli olarak yapılmaz** (2026-10-20 kararı). Uygulama hiçbir koşulda kullanıcı adına girdi olayı üretmez; uyku engelleme yalnızca güç bildirimleriyle yapılır (§7.6).
- Telefona bildirim, otomatik güncelleme, İngilizce arayüz, Intel Mac, birden fazla sahip

---

## 2. Terimler

| Terim | Anlam |
|---|---|
| Sahip | Yüzü kayıtlı tek kullanıcı |
| Nöbet | "Uzaktayım" ile başlayıp kapanana kadar süren oturum |
| Kalkan | Tüm ekranları kaplayan bulanık kilit katmanı |
| Tetikleyici | Nöbeti Kilitli durumuna geçiren olay |
| Sahip var / yok | Sahibin son 1,5 sn içinde tanınıp tanınmadığı (§5.2) |
| İz (track) | Ardışık karelerde aynı kişiye ait yüz/gövde gözlemleri |
| Mesafe eşiği | Bir yüzün/gövdenin dikkate alınması için gereken en küçük görüntü boyutu (§5.3 T1) |

---

## 3. Kullanıcı akışları

### 3.1 İlk kurulum
Kurulum sihirbazı (§8.2): izinler → sistem kontrolleri → yüz kaydı → uygulama şifresi → tercihler → deneme kilidi.

### 3.2 Nöbete başlama
1. Kullanıcı menüden "Uzaktayım"a tıklar ya da ⌃⌥⌘L'ye basar.
2. **Hazırlık** (~1 sn): ön koşullar (§5.1) kontrol edilir. Eksik varsa nöbet başlamaz, nedeni ve tek tıklık çözümü menüde gösterilir.
3. Nöbet başlar; "Nöbetçi devrede" bildirimi görünür, kamera ışığı yanar. Sahip henüz karşıda olduğu için kullanım serbesttir.
4. Sahip kalkar; 1,5 sn sonra "sahip yok" durumuna geçilir.

### 3.3 Sahip yokken biri gelir
Tetikleyici (§5.3) → kalkan iner, girdiler kapanır, olay kaydedilir. Kalkan sahip dönene kadar kalır.

### 3.4 Sahip döner
- **Kilitliyse:** yüz + göz kırpma (ya da şifre) → kalkan kalkar → olay varsa rapor açılır → dönüş davranışına göre nöbet kapanır (varsayılan) ya da sürer (§5.5).
- **Kilitli değilse:** sahip tanındığı an nöbet kapanır (varsayılan) ve "Nöbet bitti" bildirimi gelir; olay olduysa rapor açılır.
- Sahip varken menüden "Korumayı kapat" ya da ⌃⌥⌘L nöbeti kapatır. (Sahip yokken menüye tıklamak veya tuşa basmak zaten T3 tetikleyicisidir.)

### 3.5 Şifre unutuldu ve yüz tanınmıyor (kurtarma)
1. Güç tuşuna basılı tutularak Mac kapatılır (kaydedilmemiş işler kaybolabilir — son çare).
2. Açılışta FileVault macOS şifresini ister (bu Mac'te FileVault açık, otomatik giriş kapalı — V12).
3. Nöbetçi farklı bir açılış oturumunda başladığı için **Kapalı** başlar (§7.10).
4. Ayarlar → Kilit açma → "Şifremi unuttum": macOS kimlik doğrulaması (Touch ID ya da Mac şifresi) ile yeni uygulama şifresi belirlenir.

> macOS kimlik doğrulaması **yalnızca** bu sıfırlama için kullanılır. Kalkanı açmanın yolları yalnızca sahibin yüzü ve uygulama şifresidir.

---

## 4. Mimari

### 4.1 Modüller

| Modül | Tür | Sorumluluk | Bağımlılıklar |
|---|---|---|---|
| `NobetciCore` | kütüphane | Durum makinesi; tetikleme ve kilit açma kuralları; eşleştirme kararı; göz kırpma tespiti; kapak/ivme eşik mantığı; şifre doğrulama ve bekleme; olay kaydı ve rapor modeli; ayar modeli ve bütünlüğü | Foundation, CryptoKit, CommonCrypto |
| `NobetciVision` | kütüphane | Kamera yakalama; kare analizi; yüz hizalama; Core ML yüz modeli; iz takibi; sahne sağlığı; canlılık sinyalleri | Core, AVFoundation, Vision, CoreML, Accelerate |
| `NobetciSystem` | kütüphane | macOS adaptörleri: kapak sensörü, ivmeölçer, girdi filtresi, kalkan pencereleri, kiosk kilitleri, uyanık tutma, fiziksel müdahale izleme, uyku/uyanma, global kısayol, süreç yaşam döngüsü, Keychain, şifreli depo | Core, IOKit, CoreGraphics, AppKit, ServiceManagement, Security, CryptoKit, LocalAuthentication |
| `Nobetci` | uygulama | SwiftUI menü çubuğu, kurulum sihirbazı, kalkan arayüzü, ayarlar, rapor; kompozisyon kökü ve `EffectRunner` | Hepsi, SwiftUI |
| `nobetci-eval` | komut satırı aracı (dağıtılmaz) | Yüz modeli değerlendirme düzeneği; üretimdeki hattın **aynısını** kullanır | Core, Vision |
| `tools/model` | Python (uv), derleme zamanı | Ağırlık indirme (SHA-256 doğrulamalı), Core ML'e dönüştürme, eşitlik testi | — |

Kurallar:
- Core hiçbir donanıma ve arayüze dokunmaz; tüm kararlar oradadır → sahte girdilerle eksiksiz test edilebilir.
- Vision ve System birbirini bilmez; ikisi de yalnızca Core'daki protokolleri uygular.
- Uygulamada **üçüncü parti çalışma zamanı bağımlılığı yoktur** (tedarik zinciri riski). Kısayol kaydedici dahil her şey Apple framework'leriyle yazılır. Python araçları yalnızca derleme zamanında kullanılır.

### 4.2 Çekirdek: saf durum makinesi
`GuardEngine` saf bir indirgeyicidir: `reduce(state, event, context) -> (newState, [Effect])`.

- **Event:** kare özeti (`FrameSummary`), kamera sağlığı, kapak açısı örneği, ivme özeti, girdi olayı, fiziksel olay, uyku/uyanma, şifre denemesi, kullanıcı komutları (nöbet başlat/kapat), zaman tıkı, açılış.
- **Effect:** sensörleri başlat/durdur; kalkanı göster/kaldır; girdi politikasını ayarla; uyanık tutmayı aç/kapa; olay kaydet; bildirim göster; raporu göster; durumu kalıcı yaz.
- **Context:** ayarlar, enjekte edilen saat, sahip profili meta verisi.

Yan etkileri uygulama katmanındaki `EffectRunner` adaptörlere dağıtır.

### 4.3 Eşzamanlılık
- Swift 6 dil modu, katı eşzamanlılık denetimi.
- `GuardEngine`, olayları sırayla işleyen bir `actor` (`GuardCoordinator`) içinde çalışır.
- Kamera kareleri kendi seri kuyruğunda işlenir; motor yalnızca kare özetini alır.
- Girdi filtresi ayrı bir iş parçacığında, kendi run loop'unda çalışır; kararını `OSAllocatedUnfairLock` ile korunan bir politika değişkeninden okur ve **motoru beklemez** (§7.3).
- Arayüz `@MainActor`; durum `@Observable` bir modelle yansıtılır.

### 4.4 Veri akışı

```
 Kamera ──────────► Görüntü hattı ──► FrameSummary ──┐
 Kapak sensörü ───► örnek (20 Hz) ──────────────────┤
 İvmeölçer ───────► özet olaylar ───────────────────┤
 Girdi filtresi ──► girdi olayı ────────────────────┼──► GuardEngine ──► Effect'ler ──► kalkan · girdi politikası ·
 Ekran/USB/güç ───► fiziksel olay ──────────────────┤                                    uyanık tutma · kayıt ·
 Uyku/uyanma · zaman tıkı · komutlar ───────────────┘                                    bildirim · durum
```

---

## 5. Koruma mantığı

**Temel ilke:** Emin olunamayan her durumda kilitle (fail-closed). Sahip yokken yanlış alarm zararsızdır; kaçırılan bir izinsiz giriş zararlıdır.

### 5.1 Durumlar

| Durum | Açıklama | Geçişler |
|---|---|---|
| Kapalı | Kamera ve sensörler kapalı, uyku ayarları normal | Nöbet başlat → Hazırlık |
| Hazırlık | Ön koşul kontrolü (~1 sn) | Başarılı → Nöbette (sahip var ya da yok); başarısız → Kapalı + sorun listesi |
| Nöbette · sahip var | Kullanım serbest; uyanık tutma açık | Yabancı yüz (T1) ya da T12–T14 → Kilitli; sahip ≥ 1,5 sn görünmez → Nöbette · sahip yok; kapat → Kapalı |
| Nöbette · sahip yok | Ekran görünür; uyanık tutma açık; tüm tetikleyiciler etkin | Herhangi bir tetikleyici → Kilitli; sahip tanınır → dönüş davranışı (§5.5) |
| Kilitli | Kalkan + tüm girdiler kapalı + kiosk kilitleri | Yüz ya da şifre (§5.4) → dönüş davranışı (§5.5) |

**Hazırlık ön koşulları (hepsi zorunlu):** kamera izni; erişilebilirlik izni; yüz profili; uygulama şifresi; seçili kameranın açılması ve ilk 10 karenin sağlıklı gelmesi; modelin yüklenmesi; Keychain erişimi; girdi filtresinin kurulabilmesi.

**İsteğe bağlı (yoksa ilgili tetikleyici yedeğe geçer, menüde gösterilir):** kapak açısı sensörü, ivmeölçer.

**Uyarı verilen ama engellemeyen durumlar:** kamera video efektleri açık; Center Stage kapatılamadı; FileVault kapalı ya da otomatik giriş açık; Siri sesle tetikleme ya da Sesli Denetim açık.

### 5.2 Sahip varlığı
- Bir yüz izi, sahip profiliyle **kabul eşiği** `T_kabul` üzerinde ≥ 3 analiz karesinde eşleşince **sahip izi** olur.
- Doğrulanmış sahip izi, iz kopmadıkça ve skor **sürdürme eşiği** `T_sürdür` (daha düşük) üzerinde kaldıkça sahip sayılır. Bu histerezis, kötü açılarda kimliğin düşmesini önler.
- Son sahip izi gözleminden bu yana ≥ 1,5 sn geçtiyse durum "sahip yok" olur.
- Eşiklerin sayısal değerleri §6.8'deki ölçüm protokolüyle belirlenir.

### 5.3 Tetikleyiciler
- **T2–T11** yalnızca **Nöbette · sahip yok** durumunda kilide yol açar. Bunlar anlık olay değil, sürekli değerlendirilen koşullardır: örneğin kamera sahip varken örtülürse sahip 1,5 sn sonra "yok" sayılır ve koşul hâlâ sürüyorsa T6 o an tetiklenir.
- **T1** (yabancı yüz) **sahip var** durumunda da kilitler.
- **T12–T14** sistem olaylarıdır; nöbetin her alt durumunda (sahip var ya da yok) kilitler.
- "Mesafe eşiğini geçen" = görüntüdeki boyutu, seçili mesafe hassasiyetinin eşiğinden büyük olan.

| # | Tetikleyici | Algılama | Parametre (varsayılan → kalibrasyon) | Hedef süre | Ayar |
|---|---|---|---|---|---|
| T1 | Yabancı yüz | Mesafe eşiğini geçen bir yüz izi, izin ilk gözleminden itibaren **0,3 sn** içinde sahip olarak kabul edilmezse ya da 3 ardışık karede `T_red` altında kalırsa (cihaz geri bildirimiyle 0,5→0,3; dönen sahip ~9 karede tanınır). Sahibin kendi izi kötü açıda tehdit sayılmaz (iz sürekliliği). Motor üstüne 2 kare ister (tek-kare arıza koruması). | Mesafe: Yakın ≈ 0,8 m · **Orta ≈ 1,5 m** · Uzak ≈ 3 m. Yüz kutusu yüksekliği eşikleri bilinen mesafelerde ölçülerek belirlenir. | ≤ 0,5 sn | Mesafe hassasiyeti |
| T2 | Yüzsüz kişi (maske, kapüşon, arkası dönük) | Sahne ≥ 3 sn boşken (mesafe eşiğini geçen hiçbir yüz ya da gövde yokken) mesafe eşiğini geçen bir üst gövde belirir ve içinde tanınan yüz yoktur. "Sahne boşken" şartı, sahibin kalkıp uzaklaşırken görünen kendi gövdesinin kilidi tetiklemesini önler. | Gövde boyutu eşiği T1 ile aynı mesafe ölçeğinden | ≤ 0,5 sn | Aç/kapa |
| T3 | Girdi | İşaretsiz herhangi bir klavye, fare, trackpad, kaydırma, hareket ya da medya tuşu olayı. **Olay yutulur; hiçbir uygulamaya ulaşmaz.** | — | Olay anında yutulur; kalkan ≤ 100 ms | Kapatılamaz |
| T4 | Kapak açısı değişti | Taban açısından sapma ≥ eşik, 2 ardışık örnek | Eşik 3°; sensör gürültüsü ölçülerek kesinleşir. Taban nöbet başında alınır, sahip varken güncellenir. | ≤ 100 ms | Hassasiyet (Düşük/Orta/Yüksek) |
| T5 | Mac oynatıldı/kaldırıldı | İvme: yerçekimi yönünde eşik üstü sapma (eğim) ya da yüksek frekanslı enerji sıçraması | Eşikler kaydedilmiş gerçek verilerle (masa titreşimi, yanında yazı yazma, kaldırma) belirlenir | ≤ 100 ms | Hassasiyet (Düşük/Orta/Yüksek) |
| T6 | Kamera örtüldü/karartıldı | Ortalama parlaklık eşik altında ya da doku (Laplacian varyansı) çöküşü, ≥ 0,5 sn | Eşikler kayıtlı kliplerle belirlenir | ≤ 1 sn | Kapatılamaz |
| T7 | Kamera kesildi, dondu ya da değişti | 1 sn kare gelmemesi; oturum kesintisi ya da hata bildirimi; cihazın çıkarılması; sabitlenen cihaz dışında bir kameraya geçiş | — | ≤ 1 sn | Kapatılamaz |
| T8 | Kamera açısı değişti (sensörsüz Mac'lerde kapak yedeği) | Kişi yokken ardışık kareler arasında tüm görüntünün öteleme kaydı (image registration) ≥ eşik | Eşik kare genişliğinin %3'ü; kliplerle kesinleşir. Center Stage kapalı olmalı. | ≤ 0,5 sn | Aç/kapa |
| T9 | Ekran takıldı/çıkarıldı | Ekran yapılandırması değişikliği | — | ≤ 100 ms | Aç/kapa |
| T10 | USB/HID cihazı takıldı | Nöbet başındaki cihaz listesinde olmayan yeni HID ya da USB cihaz | — | ≤ 100 ms | Aç/kapa |
| T11 | Güç kaynağı değişti | Yalnızca AC ↔ pil geçişi (yüzde değişimleri sayılmaz) | — | ≤ 1 sn | Aç/kapa |
| T12 | Uyku | Uyku öncesi kalkan iner; uyanınca durum Kilitli'dir (uykuda ne olduğu bilinemez) | — | — | Kapatılamaz |
| T13 | Uygulama sonlandırıldı | Nöbetteyken çıkış yalnızca sahip varken mümkündür. Zorla sonlandırılırsa launchd yeniden başlatır ve aynı açılış oturumunda **Kilitli** başlar. | launchd `ThrottleInterval` 1 sn | ≤ 2 sn | Kapatılamaz |
| T14 | Girdi filtresi ya da izin kaybı | Filtre devre dışı kalır ve 3 denemede yeniden açılamazsa ya da erişilebilirlik izni kaybolursa | — | ≤ 0,5 sn | Kapatılamaz |

"Aç/kapa" ve "Hassasiyet" ayarlarında korumayı zayıflatan her değişiklik uygulama şifresi ister (§8.6).

### 5.4 Kilit açma

**Yüzle** — aynı iz üzerinde aşağıdakilerin hepsi birlikte sağlanmalıdır:
1. ≤ 1 sn içinde ≥ 5 analiz karesinde `T_kabul` üzerinde eşleşme (kayan pencere; ardışık değil).
2. **Canlılık:** aynı iz üzerinde son 3 sn içinde en az bir göz kırpma (§6.7). Kırpma algılanmadıysa kalkanda "Göz kırp" ipucu çıkar. **İsteğe bağlı — kullanıcı kararı (2026-10-21): varsayılan KAPALI; tanıyınca açılır.** Açıldığında fotoğrafla kandırmayı zorlaştırır (Ayarlar → Kilit açma → "Göz kırpma iste").
3. Karede mesafe eşiğini geçen başka bir yüz ya da gövde yoktur. Varsa yüzle açılmaz; kalkanda "Yanında biri var — şifre gerekli" yazar.
4. Yüz kalitesi (Vision capture quality) yeterlidir ve yüz en az Yakın mesafe eşiği boyutundadır (≈ 0,8 m ya da daha yakın).

**Sıkı mod** (ayar, varsayılan kapalı): 1–4'e ek olarak rastgele bir hareket istenir (sola / sağa / yukarı bak). İstenen yönde 3 sn içinde ≥ 15° baş dönüşü gerekir. Hareket boyunca iz kopmamalı ve skor `T_sürdür` üzerinde kalmalı; hareketin başında ve sonunda skor `T_kabul` üzerinde olmalıdır.

**Şifreyle:**
- Kalkandayken herhangi bir tuş şifre alanını gösterir. Karakterler girdi filtresinden doğrudan bu alana aktarılır ve sisteme ulaşmaz (§7.3). Return gönderir, Delete siler, Esc temizler.
- Doğrulama PBKDF2 ile yapılır (§9.2).
- **Yanlış denemeler:** 1–4. denemede bekleme yoktur; 5. yanlış → 30 sn; sonraki her yanlış → bir öncekinin 2 katı (60 sn, 120 sn, …), en fazla 15 dk. Doğru giriş (ya da yüzle açma) sayacı sıfırlar.
- Sayaç Keychain'de tutulur; uygulama yeniden başlasa da sürer. Bekleme süresi açılış oturumu içinde monoton saatle ölçülür (sistem saatini oynatmaya dayanıklı); Mac yeniden başlarsa o anki bekleme süresi baştan uygulanır.

### 5.5 Dönüş davranışı (ayar)
- **Nöbet sürsün (varsayılan — kullanıcı kararı 2026-10-21):** Kilit açılınca → Nöbette · sahip var. Kamera açık kalır (omuz üstü koruması). Nöbet, sahip varken menüdeki **"Buradayım"** ile ya da kısayolla kapatılır.
- **Nöbet kapansın:** Kilit açılınca ya da kilit olmadan sahip ≥ 1,5 sn yokluktan sonra tanınınca → Kapalı. Uyanık tutma biter, kamera kapanır.

### 5.6 Olay kaydı ve rapor
Her nöbet bir oturum kaydıdır: başlangıç ve bitiş, süre, olaylar (zaman, tür, ayrıntı) ve sayaçlar.

Olay türleri: nöbet başladı/bitti; sahip ayrıldı/döndü; tetikleyici (türüyle); kilit açıldı (yüz/şifre); yanlış şifre; sensör ya da kamera sorunu; uygulama yeniden başladı; Mac uyudu/uyandı; nöbet yeniden başlatmayla sonlandı.

Rapor kuralı: Nöbette kilit, yanlış şifre, müdahale ya da yeniden başlama olduysa rapor penceresi kilit açılınca kendiliğinden açılır. Aksi halde yalnızca "Nöbet bitti — ‹süre›, olay yok" bildirimi gelir. Kilidi tetiklemeyen, mesafe eşiğinin altında kalan kişiler rapora yazılmaz.

---

## 6. Görüntü işleme hattı

### 6.1 Kamera
- **Cihaz seçimi:** `AVCaptureDevice.DiscoverySession` ile `.builtInWideAngleCamera`. Continuity Camera ve diğer kameralar hariç tutulur. Dahili kamerası olmayan Mac'lerde kurulumda seçilen harici kamera `uniqueID` ile sabitlenir.
- **Biçim:** 1280×720, en fazla 30 fps, `alwaysDiscardsLateVideoFrames = true`.
- **Center Stage:** `centerStageControlMode = .app`, `isCenterStageEnabled = false`. Kapatılamazsa T8 devre dışı kalır ve uyarı verilir.
- **Video efektleri** (Portre, Stüdyo Işığı, arka plan değiştirme, tepkiler) etkinse uyarı verilir; bulanık arka plan uzaktaki kişileri gizler.
- **Kesinti ve hata bildirimleri** (`wasInterrupted`, `runtimeError`) T7'yi tetikler.

### 6.2 Kare analizi ve uyarlanır hız
Her kare 64×36 gri ölçekli bir görüntüye küçültülür (Accelerate/vImage); hareket enerjisi, ortalama parlaklık ve doku ölçülür.

Tam analiz şu durumlarda çalışır: hareket eşiği aşıldıysa; sahnede kişi varsa; kilitliyken yüz varsa (canlılık için 30 fps); ya da son tam analizden bu yana 500 ms geçtiyse.

Tam analizdeki istekler:
- `VNDetectFaceRectanglesRequest`
- `VNDetectFaceLandmarksRequest` — yüz yüksekliği Uzak mesafe eşiğini geçen tüm yüzler için (daha küçük yüzler yalnızca tespit edilir)
- `VNDetectFaceCaptureQualityRequest` — kilit açma için
- `VNDetectHumanRectanglesRequest(upperBodyOnly: true)` — en fazla 5 fps
- `VNTranslationalImageRegistrationRequest` — en fazla 5 fps, referans kareye göre (T8)

### 6.3 Hizalama ve yüz vektörü
- Vision yüz noktalarından 5 nokta (iki göz merkezi, burun ucu, iki ağız köşesi) alınır ve 112×112 standart ArcFace şablonuna benzerlik dönüşümüyle hizalanır.
- Modelin beklediği normalizasyon uygulanır → Core ML → L2-normalize vektör.
- Model Neural Engine'de çalışır (`computeUnits = .all`). `.mlpackage`, uygulama paketine derlenmiş `.mlmodelc` olarak girer.

### 6.4 Eşleştirme
- **Sahip profili:** kayıtta toplanan 40–60 vektör (farklı baş açıları; isteğe bağlı gözlüklü tur); model sürümüyle etiketlidir.
- **Skor:** profildeki vektörlere kosinüs benzerliğinin en yüksek 3 değerinin ortalaması.
- **Üç eşik:** `T_kabul` (ilk tanıma ve kilit açma), `T_sürdür` (doğrulanmış izi sürdürme), `T_red` (kesin yabancı). Seçim kuralları §6.8'dedir.

### 6.5 İz takibi
- Ardışık analiz kareleri arasında IoU tabanlı eşleştirme yapılır; kimlik oyları iz üzerinde birikir.
- Yabancıların yüz vektörleri yalnızca o anki karar için bellekte kullanılır; saklanmaz ve kümelenmez.

### 6.6 Sahne sağlığı
Karanlık/örtülü (T6), donma/kesinti (T7) ve kamera kayması (T8) ölçütleri küçültülmüş kareden hesaplanır. Eşikler kayıtlı kliplerle (§13.3) belirlenir ve tanılama panelinde (§13.5) canlı izlenir.

### 6.7 Canlılık
- **Göz kırpma:** Her göz için yüz noktalarından göz açıklık oranı (EAR) hesaplanır. Taban değer her iz için uyarlanır. Oran tabanın %60'ının altına inip 50–400 ms içinde geri dönerse bu bir kırpmadır.
- **Doğrulanacak (D13):** Vision göz noktalarının 30 fps'de gerçek kırpmaları güvenilir yakalaması. Yetmezse yedek: göz bölgesinden açık/kapalı sınıflandıran küçük bir Core ML modeli.
- **Sıkı mod:** Baş açıları (yaw/pitch) `VNFaceObservation`'dan okunur.
- **Bilinen sınır:** Sahibin göz kırptığı bir videoyla kandırma varsayılan modda mümkün olabilir; sıkı mod bunu zorlaştırır (§9.4).

### 6.8 Model seçimi ve değerlendirme protokolü

Adaylar:

| Aday | Kaynak | Not |
|---|---|---|
| ArcFace IResNet-50 / -100 | InsightFace (WebFace600K / Glint360K), ONNX | Ağırlık lisansı: ticari olmayan kullanım |
| AdaFace IR-50 / IR-101 | AdaFace (WebFace4M / WebFace12M), PyTorch | Düşük kaliteli görüntülerde güçlü; ağırlık lisansı dönüşüm sırasında kontrol edilir |
| FaceNet InceptionResNetV1 | facenet-pytorch (VGGFace2) | MIT kod lisansı; daha eski nesil |

Lisans notu: Ücretsiz ve özel paylaşım (hedef kitle B) için ticari olmayan lisanslar uygundur. Herkese açık ya da ticari dağıtım gündeme gelirse yeniden değerlendirilir.

Protokol:
1. **İndirme:** sabitlenmiş URL + SHA-256 doğrulaması (`tools/model`).
2. **Dönüştürme:** Core ML mlprogram, FP16. **Eşitlik:** 100 hizalanmış yüzde orijinal model ile Core ML çıktısı arasında kosinüs ≥ 0,999.
3. **Doğruluk:** `nobetci-eval`, üretimdeki hattın aynısıyla (Vision tespiti + hizalama + Core ML) LFW üzerinde çalışır: standart 6.000 çift + düşük yanlış kabul oranlarını ölçebilmek için tüm kimlikler arası sahte çiftler. Çıktılar: TAR@FAR = 1e-3, 1e-4, 1e-5; ROC; çıkarım gecikmesi; model boyutu.
4. **Seçim kuralı:** M5 Neural Engine'de çıkarım ≤ 10 ms ve model ≤ 150 MB koşuluyla TAR@FAR=1e-4 en yüksek olan aday seçilir; eşitlikte küçük olan.
5. **Eşikler:** `T_kabul` = değerlendirme kümesinde tek kare FAR ≤ 1e-4; `T_sürdür` = FAR ≤ 1e-3; `T_red` = sahibin gerçek koşul kayıtlarında FRR ≤ 1e-3 veren değer.
6. **Sahibe özel doğrulama:** Sahibin 3 ışık koşulu × gözlüklü/gözlüksüz kayıtlarında kilit açma denemelerinin ≥ %98'i 2 sn içinde başarılı olmalı.
7. Sonuçlar `docs/model-evaluation.md` dosyasına yazılır.

---

## 7. Sistem entegrasyonları

### 7.1 Kapak açısı sensörü
- `IOHIDManager` eşleşmesi: VID `0x05AC`, PID `0x8104`, UsagePage `0x20`, Usage `0x8A`.
- `IOHIDDeviceGetReport(feature, reportID 1)` → 3 bayt; açı = `bayt[2] << 8 | bayt[1]` derece. Root gerekmez (V2).
- 20 Hz okunur; cihaz giriş raporuyla değişiklik bildiriyorsa bildirim tercih edilir (D1).
- Sensör yoksa T8 (kamera kayması) yedek olarak her zaman açık olur; menüde "Kapak sensörü: yok (kamerayla)" görünür.

### 7.2 İvmeölçer
- `AppleSPUHIDDriver` (UsagePage `0xFF00`, Usage `3`) üzerinde `SensorPropertyReportingState = 1`, `SensorPropertyPowerState = 1` ve `ReportInterval` ayarlanır; cihaz 22 baytlık giriş raporları gönderir. Root gerekmez (V3).
- **Çözümleme (ön bulgu, D2):** bayt 6, 10 ve 14'te little-endian `Int32`; ÷ 65536 = g.
- Örnekleme hızı `ReportInterval = 10000 µs` ile 100 Hz'e düşürülür (D2); nöbet bitince özellikler eski değerlerine döndürülür.

### 7.3 Girdi filtresi
- İki etkin `CGEventTap`: `.cghidEventTap` ve `.cgSessionEventTap`; ikisi de `headInsertEventTap`, tüm olay türleri. Oturum seviyesindeki tap, başka süreçlerin oturum seviyesine gönderdiği sentetik olayları yakalamak içindir.
- Taplar **yalnızca nöbet süresince** (ve kurulumdaki deneme kilidinde) kuruludur; Kapalı durumda sistemde hiçbir girdi filtresi yoktur.
- **Politika** (iki tap arasında paylaşılan, kilitle korunan değişken):
  - `geçir` — Nöbette · sahip var
  - `ilkGirdideKilitle` — Nöbette · sahip yok
  - `hepsiniEngelle` — Kilitli
- `ilkGirdideKilitle`: İlk olayda tap politikayı **kendisi** `hepsiniEngelle` yapar (yarış koşulu olmasın), olayı yutar ve motora bildirir.
- `hepsiniEngelle`: Tüm olaylar yutulur. keyDown olaylarından karakter, etkin klavye düzenine göre (`UCKeyTranslate`, ölü tuş durumu dahil) çözülür ve kalkandaki şifre alanına aktarılır; Return, Delete ve Esc özel işlenir.
- Uygulama hiçbir sentetik girdi olayı üretmez; dolayısıyla filtrede "kendi olayını tanıma" istisnası yoktur. Filtreden geçen her olay gerçek ya da üçüncü taraf kaynaklıdır.
- `tapDisabledByTimeout` / `tapDisabledByUserInput` gelince tap anında yeniden etkinleştirilir; 0,5 sn'de bir sağlık kontrolü yapılır; 3 başarısız denemede T14.
- **Güvenli giriş (Secure Event Input):** Kilitlenirken uygulama öne alınır; `IsSecureEventInputEnabled()` izlenir ve tanılama kaydına yazılır (D7).

### 7.4 Kalkan pencereleri
- Her `NSScreen` için kenarlıksız bir pencere; seviye `CGShieldingWindowLevel()`; davranış `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenAuxiliary`.
- İçerik: `NSVisualEffectView` (`.behindWindow`, `.fullScreenUI`, `.active`) + koyu ton katmanı + SwiftUI kart (§8.3).
- Kilitlenirken tam güçte ve animasyonsuz görünür (geçiş sırasında içerik okunamasın); kilit açılırken 250 ms'de solar.
- Ekran yapılandırması değişince pencereler anında yeniden kurulur.
- "Şeffaflığı azalt" açıksa sistem bulanıklık yerine opak renk çizer; ekran yine okunamaz.
- **Doğrulanacak (D6):** okunamazlık. Yedekler sırasıyla: ton katmanını koyulaştırmak → `CGSSetWindowBackgroundBlurRadius` (belgelenmemiş ama iTerm2 gibi uygulamaların yıllardır kullandığı API).

### 7.5 Kiosk kilitleri
- Kilitlenince uygulama etkinleştirilir ve `NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication, .disableAppleMenu]` uygulanır.
- Menü çubuğu (accessory) uygulamasında çalışmazsa (D8): kilitliyken etkinleştirme politikası geçici olarak `.regular` yapılır.
- `applicationShouldTerminate`, nöbette (sahip yokken) ve kilitliyken iptal eder.

### 7.6 Uyanık tutma
- Nöbet boyunca `kIOPMAssertionTypePreventUserIdleDisplaySleep` ve `kIOPMAssertionTypePreventUserIdleSystemSleep` bildirimleri tutulur. Böylece Mac uyumaz, ekran kararmaz, ekran koruyucu ve boşta kalmaya bağlı otomatik kilit devreye girmez; kalkan gerektiği sürece ekranda kalır.
- Bu bildirimler yalnızca güç yönetimine "uyuma" der; **sahte girdi üretmez ve boşta kalma sayaçlarını sıfırlamaz** (`IOPMAssertionDeclareUserActivity` bile sayaçları sıfırlamaz — V6). Sen uzaktayken Slack/Teams gibi araçlar seni doğru şekilde "boşta" gösterir; bu kasıtlıdır (§1.5).
- Bildirimler nöbet bitince (Kapalı'ya geçişte) serbest bırakılır; uygulama çökerse macOS bunları otomatik temizler.
- **Doğrulanacak (D4):** Ekran koruyucu 1 dk'ya ayarlıyken 15 dk nöbette başlamaması; ekranın kararmaması; otomatik kilidin açılmaması. Yedek: `caffeinate -d -i` alt süreci (aynı bildirimleri kullanır, farklı yol).

### 7.7 Fiziksel müdahale izleme
- **Ekran:** `CGDisplayRegisterReconfigurationCallback`.
- **HID:** `IOHIDManager` eşleşme bildirimi (nöbet başındaki listede olmayan cihaz). **USB:** `IOServiceAddMatchingNotification` (`IOUSBHostDevice`).
- **Güç:** `IOPSNotificationCreateRunLoopSource` + `IOPSGetProvidingPowerSourceType` ile yalnızca AC ↔ pil geçişi.

### 7.8 Uyku/uyanma
- `NSWorkspace.willSleepNotification`: nöbetteyse kalkan iner ve durum Kilitli olarak yazılır.
- `NSWorkspace.didWakeNotification`: durum Kilitli'dir; sensör tabanları kilit açıldıktan sonra yeniden alınır.

### 7.9 Global kısayol
Carbon `RegisterEventHotKey` (izin gerektirmez). Varsayılan ⌃⌥⌘L; ayarlardan değiştirilebilir. Başka bir uygulamayla çakışırsa hata gösterilir.

### 7.10 Süreç yaşam döngüsü
- Uygulama `SMAppService.agent` ile launchd ajanı olarak kaydedilir. İki plist vardır: "Girişte başlat" açıkken `RunAtLoad = true`, kapalıyken `false` olanı kayıtlıdır. İkisinde de `KeepAlive = { SuccessfulExit = false }`, `ThrottleInterval = 1`, `ProcessType = Interactive`, `LimitLoadToSessionType = Aqua`.
- Kullanıcı uygulamayı elle açarsa ve süreç launchd yönetiminde değilse, ajan `launchctl kickstart` ile başlatılır ve elle açılan kopya çıkar (tek kopya kuralı).
- **Durum dosyası** (`state.json`, atomik yazım): nöbet/kilit durumu, açılış oturumu kimliği (`kern.bootsessionuuid`, V11), oturum kimliği.
- **Açılışta:**
  - Kayıtlı durum Nöbette ya da Kilitli **ve** açılış oturumu aynıysa → önce kalkan iner, sonra sensörler başlar (Kilitli).
  - Açılış oturumu farklıysa → Kapalı; açık kalmış oturum "yeniden başlatmayla sonlandı" olarak kapatılır.

---

## 8. Arayüz

### 8.1 Menü çubuğu
- **Simge** (şablon görsel, açık/koyu menü çubuğuna uyar): Kapalı = kalkan; Nöbette = dolu kalkan; Sorun = ünlemli kalkan. Kilitliyken menü çubuğu gizlidir.
- **Panel** (`MenuBarExtra`, pencere stili):
  - Kapalıyken: büyük "Uzaktayım" butonu (kısayol ipucuyla), durum satırı, son nöbet özeti, Ayarlar…, Çıkış.
  - Ön koşul eksikse buton yerine sorun ve tek tıklık çözüm ("Kamera izni ver" gibi).
  - Nöbetteyken: süre ("Nöbette · 12 dk"), sensör durumları (kamera, kapak, ivmeölçer, uyanık tutma) ve "Korumayı kapat".

### 8.2 Kurulum sihirbazı
1. **Tanıtım** ve gizlilik sözü (hiçbir veri cihazdan çıkmaz).
2. **İzinler:** kamera, erişilebilirlik, bildirimler. Her birinin gerekçesi tek cümleyle yazılır; izin verilince sihirbaz kendiliğinden ilerler.
3. **Sistem kontrolleri:** FileVault, otomatik giriş, Siri sesle tetikleme, Sesli Denetim. Risk varsa açıklamalı uyarı (engellemez).
4. **Yüz kaydı:** dairesel canlı önizleme; baş çevrilerek halka doldurulur; ışık, netlik ve tek yüz denetimi; isteğe bağlı gözlüklü tur; sonunda doğrulama ("Şimdi seni tanıyabiliyor muyum?").
5. **Uygulama şifresi:** en az 6 karakter. Tekrar girişi kalkandaki **aynı yakalama yöntemiyle** yapılır; böylece klavye düzeni farkları yüzünden şifrenin kalkanda yazılamaması önlenir.
6. **Tercihler:** dönüş davranışı, kısayol, girişte başlat (varsayılan açık).
7. **Deneme kilidi:** kalkan gerçekten iner, kullanıcı yüzüyle açar.

### 8.3 Kalkan arayüzü
Ortada cam efektli bir kart:
- kilit simgesi
- "‹Ad›'ın Mac'i korunuyor" (`NSFullUserName`)
- "Kamera etkin" satırı (şeffaflık: yaklaşan kişi kameranın açık olduğunu görür)
- saat ve gün
- durum metni: "Seni arıyorum…", "Merhaba ‹Ad›, göz kırp", "Sola bak" (sıkı mod), "Yanında biri var — şifre gerekli", "‹n› sn sonra tekrar dene"
- bir tuşa basınca beliren şifre alanı; yanlış girişte sarsılma animasyonu

### 8.4 "Sen yokken olanlar" raporu
- Üst özet: "47 dk · 1 kilit · 3 olay · 0 yanlış şifre".
- Zaman çizelgesi: saat, tür simgesi, açıklama.
- Geçmiş nöbetler; geçmişi silme.

### 8.5 Ayarlar

| Sekme | Ayar | Varsayılan |
|---|---|---|
| Genel | Girişte başlat | Açık |
| | Klavye kısayolu | ⌃⌥⌘L |
| | Dönüş davranışı | Nöbet sürsün |
| Algılama | Mesafe hassasiyeti | Orta (≈ 1,5 m) |
| | Kapak hassasiyeti | Orta |
| | Hareket hassasiyeti | Orta |
| | Yüzsüz kişi algılama (T2) | Açık |
| | Kamera kayması algılama (T8) | Açık |
| | Ekran (T9) / USB-HID (T10) / güç kaynağı (T11) tetikleyicileri | Açık |
| Kilit açma | Sıkı mod | Kapalı |
| | Yüz profilini yenile / gözlüklü profil ekle | — |
| | Şifreyi değiştir / Şifremi unuttum | — |
| Geçmiş | Nöbet geçmişini saklama süresi | 30 gün |
| | Geçmişi sil | — |
| Hakkında | Sürüm, gizlilik açıklaması, tanılama günlüğünü dışa aktar, Nöbetçi'yi kaldır | — |

### 8.6 Hassas işlemler
Uygulama şifresi isteyen işlemler:
- korumayı zayıflatan her ayar: bir tetikleyiciyi kapatmak, hassasiyeti düşürmek (mesafeyi Yakın'a çekmek dahil), sıkı modu kapatmak
- yüz profili değişiklikleri ve şifre değişikliği
- raporları görüntüleme ve silme
- Nöbetçi'yi kaldırma

Başarılı bir kilit açma ya da şifre girişinden sonra 5 dk boyunca şifre tekrar sorulmaz. "Şifremi unuttum" yalnızca macOS kimlik doğrulamasıyla çalışır (§3.5).

### 8.7 Görsel dil, erişilebilirlik, yerelleştirme
- macOS 26'da Liquid Glass (`glassEffect`); macOS 14–15'te eşdeğer sistem materyalleri. SF Symbols, sistem fontu, açık/koyu mod, sistem vurgu rengi.
- Özel uygulama ikonu (`.icns`, `iconutil` ile üretilir).
- Tüm öğelerde VoiceOver etiketleri; ayarlar ve sihirbazda klavyeyle tam gezinme.
- Türkçe; tüm metinler tek kaynakta (`Localizable.strings`, `tr`). İngilizce ileride eklenebilir.
- Renk, boşluk ve animasyon ayrıntıları uygulama aşamasında gerçek ekran görüntüleri üzerinden kullanıcıyla birlikte onaylanır.

---

## 9. Veri ve güvenlik

### 9.1 Saklanan veriler

| Veri | Yer | Koruma | Saklama |
|---|---|---|---|
| Yüz profili (yalnızca vektörler + model sürümü; ham görüntü yok) | `~/Library/Application Support/Nöbetçi/profile.bin` | AES-GCM-256, anahtar Keychain'de | Silinene ya da yenilenene kadar |
| Oturum kayıtları | `…/Nöbetçi/sessions/` | AES-GCM-256 | Ayara göre (varsayılan 30 gün) |
| Ayarlar | `…/Nöbetçi/settings.json` | HMAC-SHA256 imzalı; imza bozuksa en güvenli varsayılanlar + uyarı | Kalıcı |
| Şifre özeti + deneme sayacı | Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Kalıcı |
| Şifreleme ve HMAC anahtarları | Keychain | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, iCloud senkronizasyonu kapalı | Kalıcı |
| Çalışma durumu | `…/Nöbetçi/state.json` | Gizli değil | Geçici |
| Tanılama günlüğü | `os.Logger` (kişisel veri içermez) | — | Sistem yönetir |

Ayarlar `UserDefaults` yerine imzalı dosyada tutulur; böylece mod kapalıyken Terminal'den `defaults write` ile korumayı sessizce zayıflatmak mümkün olmaz.

Model değişirse yüz profili uyumsuz hale gelir ve kullanıcıdan yeniden kayıt istenir (~1 dk). Ham yüz görüntüsü saklamamanın bilinçli bedeli budur.

### 9.2 Kriptografi
- **Simetrik şifreleme:** CryptoKit AES-GCM-256, her dosya için rastgele nonce.
- **Ayar bütünlüğü:** CryptoKit HMAC-SHA256, ayrı bir Keychain anahtarıyla.
- **Şifre:** PBKDF2-HMAC-SHA256 (CommonCrypto), 16 bayt rastgele tuz, 32 bayt çıktı, sabit zamanlı karşılaştırma. Yineleme sayısı kurulumda bu Mac'te ~250 ms sürecek şekilde ölçülür; alt sınır 600.000.
- **Rastgelelik:** `SecRandomCopyBytes`.

### 9.3 Ağ
Uygulama hiçbir ağ API'si kullanmaz. Kabul testinde nöbet boyunca ağ bağlantısı olmadığı `lsof -i -a -p <pid>` ile doğrulanır.

### 9.4 Tehdit modeli
**Saldırgan:** Mac'in başına fiziksel olarak geçen, sahibin şifrelerini bilmeyen, kısa süre (dakikalar) erişimi olan, yönetici ya da uzaktan erişimi olmayan biri. Elinde sahibin fotoğrafı ya da videosu olan bir telefon bulunabilir.

**Amaçları:** ekranı okumak; hesapları kullanmak (ör. mesaj göndermek); veri almak; korumayı kapatmak ya da zayıflatmak.

**Kalan riskler:**

| Risk | Durum / önlem |
|---|---|
| Sahibin fotoğrafı/videosuyla kandırma | Göz kırpma varsayılan KAPALI (kullanıcı kararı) → basılı fotoğraf bile teorik olarak yeterli olabilir; "Göz kırpma iste" ve sıkı mod zorlaştırır |
| Tek yumurta ikizi ya da çok benzer akraba | Ölçülen FAR ile sınırlı; şifre her zaman alternatif |
| Siri / Sesli Denetim ile sesli komut | Bu Mac'te Siri kapalı (V14); kurulumda tespit edilip uyarı verilir |
| Başka bir sürecin doğrudan bir uygulamaya olay göndermesi (`CGEventPostToPid`) | Önceden kurulu, erişilebilirlik izinli bir süreç gerektirir — kapsam dışı; davranış testte belgelenir (D7) |
| Güç tuşu (uyku / zorla kapatma) | Engellenemez; iki sonuç da güvenlidir (T12, §3.5) |
| Işıkların kapanması | Kamera kararır → kilit (tasarım gereği; sahip yokken zararsız) |
| Kalabalık ofiste yanlış alarm | Mesafe ayarı; sahip yokken zararsız |
| Model ağırlıklarının ticari olmayan lisansı | Hedef kitle B için uygun; herkese açık dağıtımda yeniden değerlendirilir |
| Belgelenmemiş blur API'sine ihtiyaç doğarsa | İleride bozulabilir; yedeği koyu ton katmanı |

---

## 10. Hata durumları ve kurtarma

| Durum | Davranış |
|---|---|
| Kamera izni yok | Nöbet başlamaz; menüde "Kamera izni ver" |
| Erişilebilirlik izni yok | Nöbet başlamaz (girdi engellenemez); menüde "Erişilebilirlik izni ver" |
| Yüz profili ya da şifre yok | Nöbet başlamaz; kurulum sihirbazına yönlendirilir |
| Kamera açılamıyor | Hazırlıktaysa nöbet başlamaz; nöbetteyse T7 → Kilitli |
| Kamera efektleri açık / Center Stage kapatılamıyor | Uyarı; Center Stage kapatılamazsa T8 devre dışı |
| Kapak sensörü yok | T8 yedek olarak kullanılır; menüde gösterilir |
| İvmeölçer yok ya da okunamıyor | T5 devre dışı; menüde gösterilir |
| Girdi filtresi devre dışı kaldı | Anında yeniden etkinleştirme; 3 denemede başarısızsa T14 |
| Erişilebilirlik izni nöbette kayboldu | T14 → Kilitli (kalkan + kiosk sürer); olay kaydı |
| Model yüklenemedi | Nöbet başlamaz; "Yeniden kur" önerisi |
| Keychain erişilemiyor | Nöbet başlamaz |
| Ayar dosyasının imzası bozuk | En güvenli varsayılanlar + uyarı; olay kaydı |
| Disk dolu | Oturum kaydı yazılamaz; koruma etkilenmez; menüde uyarı |
| Uygulama çöktü ya da öldürüldü | launchd ≤ 1–2 sn'de yeniden başlatır → Kilitli (T13) |
| Mac yeniden başladı | Kapalı başlar; açık oturum "yeniden başlatmayla sonlandı" olarak raporlanır |
| Şifre unutuldu ve yüz tanınmıyor | Kurtarma yolu (§3.5) |
| Uyku | Önce kalkan iner; uyanınca Kilitli (T12) |
| Ekran eklendi/çıkarıldı | Kalkan yeni ekrana anında; nöbette ve sahip yokken T9 |

---

## 11. Performans bütçeleri
Hepsi ölçülür ve `docs/test-report.md` dosyasına yazılır (D15).

| Ölçüt | Hedef |
|---|---|
| Boş, hareketsiz sahnede ortalama CPU | < %5 (tek çekirdek) |
| Kişi varken ortalama CPU | < %25 |
| Bellek | < 300 MB |
| Tetik → kalkan görünür: girdi, kapak, ivme, ekran, USB | ≤ 100 ms |
| Tetik → kalkan: yabancı yüz, yüzsüz kişi, kamera kayması | ≤ 500 ms |
| Tetik → kalkan: kamera örtüldü ya da kesildi | ≤ 1 sn |
| Yüz kadraja girdi → kilit açıldı (ortanca) | ≤ 1,5 sn |
| Şifre doğrulama | ≤ 300 ms |
| Zorla sonlandırma → kilitli yeniden açılış | ≤ 2 sn |
| Yüz vektörü çıkarımı (Neural Engine) | ≤ 10 ms |
| 30 dk nöbette enerji | Ölçülüp raporlanır; Etkinlik Monitörü "Enerji Etkisi" düşük |

---

## 12. Derleme ve dağıtım

### 12.1 Depo yapısı

```
Nobetci/
├── Package.swift
├── Makefile
├── VERSION · CHANGELOG.md · README.md · KURULUM.md
├── Sources/
│   ├── NobetciCore/
│   ├── NobetciVision/
│   ├── NobetciSystem/
│   ├── Nobetci/            (uygulama)
│   └── nobetci-eval/       (değerlendirme aracı)
├── Tests/
│   ├── NobetciCoreTests/
│   ├── NobetciVisionTests/
│   └── NobetciSystemTests/
├── Resources/              (Info.plist, entitlements, LaunchAgents/*.plist, Localizable.strings, ikon kaynakları)
├── tools/
│   ├── model/              (uv projesi: indirme, dönüştürme, eşitlik testi)
│   └── probes/             (tasarım aşamasındaki doğrulama deneyleri — §15.1 kanıtları)
└── docs/
    ├── superpowers/specs/  · superpowers/plans/
    ├── model-evaluation.md
    └── test-report.md
```

Büyük ikili dosyalar (model ağırlıkları, `.mlpackage`, veri setleri) ve kişisel veri içeren test klipleri git'e girmez. Model `make model` ile yeniden üretilir (SHA-256 sabitli).

### 12.2 Komutlar

| Komut | İş |
|---|---|
| `make cert` | Kendinden imzalı kod imzalama sertifikasını oluşturur (bir kez) |
| `make model` | Ağırlıkları indirir, doğrular, Core ML'e çevirir, eşitliği test eder |
| `make test` | Tüm testler (Swift Testing; Command Line Tools için gereken bayraklar Makefile'da — V9) |
| `make coverage` | Kod kapsamı raporu |
| `make eval` | Model değerlendirmesi → `docs/model-evaluation.md` |
| `make app` | Release derleme → `build/Nöbetçi.app` (Info.plist, kaynaklar, derlenmiş model, ajan plist'leri, ikon) + imzalama |
| `make dist` | `Nöbetçi-<sürüm>.dmg` |
| `make install` | `/Applications` altına kurar |

### 12.3 Paket bilgileri
- Paket kimliği `com.halil.nobetci`; ad "Nöbetçi"; `LSUIElement = true`; `LSMinimumSystemVersion = 14.0`; yalnızca arm64.
- `NSCameraUsageDescription`: "Nöbetçi, sen yokken bilgisayarının başına kimin geçtiğini anlamak için kamerayı kullanır. Görüntüler cihazdan çıkmaz."
- Hardened runtime; yetki: `com.apple.security.device.camera`.
- App Sandbox kullanılmaz: etkin girdi filtresi ve IOKit HID sensör erişimi gerekir; uygulama App Store'a girmeyeceği için sandbox zorunlu değildir.

### 12.4 İmzalama
- `make cert`, kullanıcının giriş anahtar zincirinde "Nöbetçi Code Signing" adlı kendinden imzalı bir sertifika (codeSigning EKU) oluşturur. Bu Mac'te şu an hiç imzalama kimliği yoktur (V13).
- Amaç sabit bir *designated requirement*: yeni sürümler kurulduğunda kamera ve erişilebilirlik izinleri korunur (D11).

### 12.5 Kurulum (son kullanıcı)
`KURULUM.md`: DMG'yi aç → Nöbetçi'yi Applications'a sürükle → ilk açılışta Gatekeeper uyarısı → Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç** → kurulum sihirbazı.

### 12.6 Sürümleme
SemVer. `VERSION` dosyası `CFBundleShortVersionString` ve `CFBundleVersion` değerlerini besler; değişiklikler `CHANGELOG.md` dosyasına yazılır.

---

## 13. Test stratejisi

### 13.1 Birim testleri (Swift Testing)
- **Core:** durum makinesinin her geçişi; her tetikleyicinin hem tetiklediği hem tetiklemediği durumlar (sahip var/yok, ayar kapalı); kilit açma koşullarının her birinin tek tek eksik olduğu durumlar; dönüş davranışı; rapor üretimi; şifre özeti, sabit zamanlı karşılaştırma, bekleme süresi (enjekte saatle); EAR tabanlı kırpma tespiti (sentetik ve kaydedilmiş nokta dizileri); kapak ve ivme eşikleri (kaydedilmiş izler); ayar bütünlüğü.
- **Vision:** hizalama dönüşümü (bilinen noktalar → beklenen matris), skor hesabı, iz eşleştirme, sahne sağlığı ölçütleri (sentetik görüntüler).
- **System:** şifreli depo (yaz/oku/bozulma tespiti), Keychain sarmalayıcısı, ivmeölçer rapor çözümleme, durum dosyası ve açılış oturumu mantığı.
- **Hedef:** Core'da satır kapsamı ≥ %90 (D19).

### 13.2 Model değerlendirmesi
§6.8'deki protokol.

### 13.3 Entegrasyon testleri (kayıtlı veriyle)
- Sahibin izniyle kaydedilen kısa klipler (sahip oturuyor ve kalkıyor; telefonda başka birinin videosu; kamera elle kapatılıyor; ışık kapanıyor; kapak oynatılıyor) ve sensör izleri, kaydet-oynat düzeneğiyle gerçek görüntü hattından ve motordan geçirilir; beklenen olay dizileri doğrulanır.
- Klipler kişisel veri içerdiği için git'e girmez; yerel bir klasörde tutulur. Klipler yoksa bu testler atlanır ve atlandıkları raporlanır.

### 13.4 Kabul testleri (gerçek Mac'te, kullanıcıyla)
Her madde ölçümüyle birlikte `docs/test-report.md` dosyasına yazılır.

1. **Tetikleyiciler:** T1–T14'ün her biri, tepki süresi ölçülerek.
2. **Girdi engelleme matrisi:** Cmd+Tab, Cmd+Space, Cmd+Opt+Esc, Cmd+Q, Ctrl+Cmd+Q, F3 / Ctrl+↑ / 3-4 parmakla kaydırma, Launchpad, Cmd+Shift+3/4/5, ekran köşeleri, Fn/Globe, dikte, harici klavye ve fare. Aynı matris Terminal'in "Güvenli Klavye Girişi" açıkken tekrarlanır. Başka bir süreçten HID seviyesine, oturum seviyesine ve `CGEventPostToPid` ile sentetik olay gönderilir; sonuçlar belgelenir.
3. **Kalkan kapsaması:** menü çubuğu, Dock, bildirimler, Spotlight, Mission Control, tam ekran uygulama, harici ekran.
4. **Blur okunamazlığı:** 12–72 pt, yüksek kontrastlı test sayfası kalkanın arkasındayken ekran görüntüsü alınır; hiçbir yazı okunamamalıdır.
5. **Kilit açma:** Sahip (3 ışık koşulu, gözlüklü/gözlüksüz) ≥ %98 başarı, ≤ 2 sn. Basılı fotoğraf ve telefon ekranında fotoğraf ile açılmamalı. Göz kırpan video: varsayılan modda sonuç kaydedilir; sıkı modda açılmamalı.
6. **Şifre:** Türkçe karakterler (ğ ü ş ı ö ç), Option karakterleri, ölü tuşlar; bekleme süreleri; uygulama yeniden başlatılınca sayacın korunması.
7. **Uyanık tutma:** 15 dk nöbette Mac uyumuyor; ekran koruyucu 1 dk'ya ayarlıyken başlamıyor; ekran kararmıyor; otomatik kilit açılmıyor. Ayrıca `pmset -g assertions` çıktısında yalnızca uyku engelleme bildirimleri görünüyor, `UserIsActive` yok.
8. **Yaşam döngüsü:** `kill -9` → ≤ 2 sn'de kilitli açılış; arka arkaya iki kez; uyku/uyanma; yeniden başlatma → Kapalı başlangıç; elle açma → tek kopya.
9. **İmza:** yeniden derleyip kurunca izinler korunuyor; başka bir Mac'te "Yine de Aç" akışı.
10. **Gizlilik:** nöbet boyunca ağ bağlantısı yok (`lsof`); diskte şifresiz yüz verisi yok.
11. **Performans:** §11 bütçeleri (30 dk ölçüm).
12. **Sürüm uyumu:** Geliştirme Mac'i macOS 26.5'tir; macOS 14/15 uyumu için kabul testlerinin bir alt kümesi ikinci bir Mac'te koşulur (D21).

### 13.5 Tanılama paneli (yalnızca debug derlemesinde)
- Canlı sinyaller: benzerlik skorları, iz kimlikleri, EAR, kapak açısı, ivme, kare ve analiz hızı, CPU, girdi filtresi ve secure input durumu.
- Rehberli senaryolar ("Şimdi kapağı oynat" gibi) ve otomatik tepki süresi ölçümü; sonuçlar test raporuna aktarılabilir.

---

## 14. Önerilen uygulama sırası
Ayrıntılı plan ayrı bir dokümanda (`docs/superpowers/plans/`) yazılacaktır.

1. Depo iskeleti, Makefile, test altyapısı, imza sertifikası, `.app` paketleme.
2. **Erken risk doğrulamaları:** D4 (uyanık tutma), D5–D6 (kalkan), D7 (girdi matrisi), D8–D9 (kiosk ve etkinleştirme), D10 (yaşam döngüsü), D11 (imza). Tasarımın en riskli kısımları bunlardır; sonuçlarına göre ilgili yedek planlar devreye alınır.
3. Model değerlendirme ve seçim (§6.8).
4. Core: durum makinesi ve kurallar (TDD).
5. Vision hattı.
6. System adaptörleri.
7. Arayüz: menü, sihirbaz, kalkan, ayarlar, rapor.
8. Kabul testleri, performans ölçümleri, dağıtım.

---

## 15. Doğrulama kaydı

### 15.1 Doğrulananlar (2026-10-20, geliştirme Mac'inde)
Deney betikleri `tools/probes/` altındadır.

| # | Bulgu | Kanıt |
|---|---|---|
| V1 | MacBook Pro (Mac17,2), Apple M5, macOS 26.5.1. Xcode yok; Command Line Tools + Swift 6.3.2 var | `sw_vers`, `sysctl hw.model`, `swift --version` |
| V2 | Kapak açısı root olmadan okunuyor: `IOHIDDeviceGetReport` → `[01 65 00]` = 101° | `tools/probes/lid.swift` |
| V3 | İvmeölçer root olmadan okunuyor: özellik yazımları `0x0` döndü; 2 sn'de 1605 giriş raporu (22 bayt); masadayken (0,019; 0,018; −1,009) g, büyüklük ≈ 1,01 g; istemci kapanınca `ReportInterval` 0'a döndü | `tools/probes/accel.swift`, `ioreg` |
| V4 | Kameralar: dahili "MacBook Pro Camera" + iPhone (Continuity Camera) | `system_profiler SPCameraDataType` |
| V5 | Slack (Electron/Chromium) boşta süresini `CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType)` ile ölçer. *(Tasarım kararı: bu sayaca dokunulmaz, §1.5.)* | Chromium `ui/base/idle/idle_mac.mm` |
| V6 | `IOPMAssertionDeclareUserActivity` başarılı döner (`0x0`) ama ne CGEventSource ne de HIDIdleTime sayacını sıfırlar (5,09 → 5,60 sn). Güç bildirimleri boşta kalma sayaçlarından bağımsızdır; §7.6 bu yüzden yalnızca onları kullanır | `tools/probes/idle.swift` (test A) |
| V7 | Sentetik girdi olayları boşta kalma sayaçlarını sıfırlar (HIDIdleTime 5,69 → 0,50 sn). *(Bu bulgu, sahte etkinlik özelliğinin çıkarılma gerekçesini doğrular: sayaçları kandırmanın tek yolu sahte girdidir; §1.5.)* | `tools/probes/idle.swift` (test B, C) |
| V8 | SwiftPM + Command Line Tools ile SwiftUI `MenuBarExtra` uygulaması (AVFoundation, Vision, CoreML içeren) derleniyor | `tools/probes/swiftpm-clt` |
| V9 | Swift Testing, Command Line Tools ile şu bayraklarla çalışıyor: `-Xswiftc -F -Xswiftc <CLT>/Library/Developer/Frameworks`, `-Xswiftc -plugin-path -Xswiftc <CLT>/usr/lib/swift/host/plugins/testing`, `-Xlinker -F -Xlinker <CLT>/Library/Developer/Frameworks`, `-Xlinker -rpath -Xlinker <CLT>/Library/Developer/Frameworks`, `-Xlinker -rpath -Xlinker <CLT>/Library/Developer/usr/lib` (`<CLT>` = `/Library/Developer/CommandLineTools`). Bayraksız `no such module 'Testing'` hatası. XCTest CLT'de yok | `tools/probes/swiftpm-clt` (2/2 test geçti) |
| V10 | uv + Python 3.12 + torch 2.14.1 + coremltools 9.0 ile PyTorch → Core ML (mlprogram, FP16) dönüşümü; eşitlik kosinüsü 1,0. `MLModel.compileModel` Xcode olmadan çalışma anında derliyor; CPU, GPU ve Neural Engine'de çıkarım çalışıyor | `tools/probes/coreml` |
| V11 | `kern.bootsessionuuid` mevcut | `sysctl` |
| V12 | FileVault açık; `autoLoginUser` tanımlı değil; ekran kilidi gecikmesi 300 sn | `fdesetup status`, `defaults read`, `sysadminctl -screenLock status` |
| V13 | Yüklü kod imzalama kimliği yok | `security find-identity -v -p codesigning` |
| V14 | Siri kapalı (`com.apple.assistant.support` → `Assistant Enabled = 0`). `com.apple.universalaccess` içinde Sesli Denetim izi yok; kesin tespit yöntemi D20'de doğrulanacak | `defaults read` |
| V15 | Geliştirme Mac'i **Türkçe Q** düzeninde (`com.apple.keylayout.Turkish-QWERTY-PC`). Bu düzende ölü tuşlar (`^`=shift+key20, `~`/`¨`/`´`/`` ` ``=option) ve Option karakterleri (`@`=key12, `€`=key14, `₺`=key17) var. `UCKeyTranslate`, `deadKeyState` taşınarak hepsini doğru üretiyor → şifre yakalama bu API ile yapılacak | `tools/probes/keylayout.swift` |
| V16 | `swift test --enable-code-coverage` CLT ile çalışıyor; `.build/.../codecov/default.profdata` ve `.xctest` ikilisinden `xcrun llvm-cov report` kapsam raporu üretiyor (`llvm-cov`, `llvm-profdata` CLT'de mevcut) | CLT `llvm-cov` çalıştırması |

### 15.2 Doğrulanacaklar (uygulama aşamasında)

| # | Konu | Test | Yedek plan |
|---|---|---|---|
| D1 | Kapak açısının hareketle değişmesi, gürültüsü, giriş raporu desteği | Tanılama paneliyle kapağı oynatma | T8 (kamera kayması) |
| D2 | İvme ekseni ve ölçeği; örnekleme hızını düşürme; güç etkisi | Mac'i eğme ve kaldırma kayıtları | T5'i devre dışı bırakma |
| D3 | ~~Sahte etkinlikle Slack/Teams sayaçlarını sıfırlama~~ — özellik çıkarıldı (§1.5), doğrulama gereksiz | — | — |
| D4 | Ekran koruyucu, ekran uykusu ve otomatik kilidin yalnızca güç bildirimleriyle engellenmesi | Ekran koruyucu 1 dk'ya ayarlıyken 15 dk nöbet; `pmset -g assertions` | `caffeinate -d -i` alt süreci |
| D5 | Kalkan seviyesinin her şeyi örtmesi | §13.4-3 | Pencere seviyesi ve davranış ayarları |
| D6 | Blur okunamazlığı | §13.4-4 | Koyu ton → `CGSSetWindowBackgroundBlurRadius` |
| D7 | Girdi engelleme matrisi, secure input, başka süreçlerden gelen olaylar | §13.4-2 | Ek tap seviyesi; kiosk; kalan risk olarak belgeleme |
| D8 | Accessory uygulamada `presentationOptions` | Kilitliyken Cmd+Tab / Force Quit denemesi | Kilitliyken `.regular` etkinleştirme politikası |
| D9 | macOS 26'da kilitlenince uygulamanın öne geçebilmesi | Başka uygulama öndeyken kilitleme | Tap tabanlı tam engelleme öne geçmeye bağlı değil |
| D10 | `SMAppService` ajanı, `KeepAlive`, `ThrottleInterval = 1`, elle açma devri | `kill -9` ölçümleri | Karşılıklı bekçi (watchdog) yardımcı süreç |
| D11 | Kendinden imzalı sertifikayla imzalama ve TCC izinlerinin kalıcılığı | Yeniden derle-kur | Ücretsiz Apple Development sertifikası (Xcode kurulumu gerektirir) |
| D12 | Center Stage'i kapatma ve video efektlerini tespit API'leri | Çalışma anında okuma ve ayarlama | T8'i kapatıp uyarı verme |
| D13 | Vision göz noktalarıyla kırpma tespitinin güvenilirliği | Tanılama panelinde 50 gerçek kırpma | Göz durumu sınıflandıran Core ML modeli |
| D14 | Aday modellerin dönüşümü, doğruluğu ve gecikmesi | §6.8 | Bir sonraki aday |
| D15 | Performans bütçeleri | §11 | Analiz hızı ve çözünürlük ayarı |
| D16 | Ağ trafiği olmaması | `lsof` | — (ağ kodu yok) |
| D17 | Ekran, HID, USB ve güç bildirimlerinin beklendiği gibi gelmesi | Takıp çıkarma testleri | Yoklama (polling) |
| D18 | Şifre yakalamada Türkçe düzen, Option karakterleri ve ölü tuşlar | ~~Ön doğrulama V15'te yapıldı~~ · kalkanda uçtan uca §13.4-6 | Kurulumda karakter kısıtı |
| D19 | ~~`llvm-cov` kod kapsamı aracının CLT'de kullanılabilirliği~~ → **V16'da doğrulandı** | — | — |
| D20 | Sesli Denetim'in açık olup olmadığının güvenilir tespiti | Ayarı açıp kapatarak | Kurulumda kullanıcıya sorma |
| D21 | macOS 14/15 uyumluluğu (geliştirme Mac'i macOS 26.5) | İkinci bir Mac'te (macOS 14/15) kabul alt kümesi | Gerekirse minimum sürümü yükseltme |

---

## 16. Görüşmede alınan kararlar

| Konu | Karar |
|---|---|
| Hedef kitle | B — bireysel kullanıcılar; DMG ile dağıtım (App Store yok) |
| Dönüş davranışı | C — ayar; varsayılan "nöbet kapansın" |
| Ekstralar | "Sen yokken olanlar" raporu ✓ · klavye kısayolu ✓ · fotoğraf ✗ (önce seçildi, sonra kullanıcı kararıyla çıkarıldı) · gerçek macOS kilidi ✗ (yerine yalnızca yüz + uygulama şifresi) · ayrı "uyanık tut" modu ✗ · sahte etkinlik/"aktif görünme" ✗ (etik gerekçeyle çıkarıldı) · telefon bildirimi ✗ |
| Yaklaşım | Native Swift + Apple Vision + Core ML yüz tanıma modeli |
| Blur | Canlı sistem blur'u (ekran kaydı izni istenmez) |
| Canlılık | Göz kırpma; sıkı mod: rastgele baş hareketi |
| Uyku sonrası | Her zaman Kilitli |
| Fiziksel müdahale | Ekran, USB/HID ve şarj kablosu değişiklikleri tetikler |
| Sahte etkinlik | Yapılmaz: uygulama kullanıcı adına girdi üretmez; yalnızca uyku engellenir (§1.5, §7.6) |
| Kalite çıtası | En profesyonel çözüm; maliyetten kısılmaz; varsayımla iş yapılmaz; testler yapılır |

## 17. Fotoğraf (geri alınan karar, 2026-10-21)

Kullanıcı isteğiyle geri eklendi: "Uzaktayım aktifken ve ben yokken hareket algılandığında veya yabancı bir yüz gördüğünde fotoğraf çeksin; döndüğümde kimlerin yaklaştığını göreyim."

- **Ne zaman:** sahip yokken kadrajda kişi görülünce; her kilit tetikleyicisinde; yanlış şifrede. Sahip karşıdayken çekilmez.
- **Hız sınırı:** en az 3 sn arayla, nöbet başına en fazla 50 (`SnapshotPolicy`, TDD).
- **Nerede:** `~/Library/Application Support/Nöbetçi/snap-*.bin`, AES-GCM-256 şifreli (anahtar Keychain), ~720 px JPEG. **Ağ yok.**
- **Saklama:** varsayılan **1 gün** (1/7/30 seçilebilir, kullanıcı kararı 2026-10-21); budama açılışta, nöbet başında, galeri açılışında ve ayar değişince çalışır. Künyeler `photos-index.bin` (AES-GCM) içinde tutulur; dizin kaybolursa dosya tarihine göre ikinci bir süpürme yapılır. Tavan: 500 künye.
- **Görüntüleme (üç yol):**
  1. **Dönüşte kendiliğinden:** sahip yokken çekilmiş ve henüz gösterilmemiş fotoğraf varsa, yüz (ya da şifre) ile kilit açılır açılmaz galeri açılır — "Buradayım" beklenmez (`GuardEffect.showSnapshots`). Her fotoğraf yalnızca bir kez gösterilir.
  2. **Menü → Fotoğraflar:** tüm kayıtlı fotoğraflar, yeniden eskiye; düğmede adet rozeti.
  3. **"Buradayım" raporu:** o nöbetin fotoğrafları olay çizelgesiyle birlikte (burada ayrıca uyarı penceresi açılmaz).
- **Galeri:** ızgara, büyütme, tek tek silme, "tümünü sil" (onaylı), saklama süresi altbilgisi.
- **Şeffaflık:** kalkan kartında "Kamera etkin" yazar; nöbet dışında kamera kapalıdır (yeşil ışık söner).
- **Not:** Ortak/çalışma alanlarında üçüncü kişilerin görüntüsünü kaydetmek yerel mevzuata (ör. KVKK) tabi olabilir; özellik kullanıcı tercihiyle açıktır ve kapatılabilir.


## 18. Kimlik çapası — yanlış "sahip yok" kararının kökten çözümü (2026-10-21)

**Belirti (cihazda, kullanıcı kanıtı):** Kullanıcı masasında otururken telefonuna baktığında
uygulama (a) ekranı "girdi" sebebiyle kilitliyor, (b) bir dakika boyunca kullanıcının *kendi*
yüzünü "kadrajda yabancı" diye fotoğraflıyordu (12 kare, 16:44:32–16:45:35).

**Kök neden:** Varlık kararı yalnızca "bu karede yüz eşleşti mi" sorusuna bağlıydı.
`OwnerPresence` 1,5 sn tanıma göremeyince `absent`'e düşüyordu; `VisionPipeline`'daki iz
hafızası da 1,5 sn ile sınırlıydı. Oysa telefona bakmak, burun kaşımak, başı çevirmek yüzü
saniyelerce *okunamaz* yapar — ama kişi masadadır. Sistem "yüzünü okuyamıyorum" ile
"masadan kalktın" arasında ayrım yapmıyordu.

**Çözüm — kimlik çapası (`OwnerAnchor`):** Kimlik kare kare tanımaya değil, kesintisiz **ize**
bağlanır. Üç kademe:
1. **Tanıma** — yüz eşleşti: çapa bu ize bağlanır (en güçlü kanıt, varlığı *kurar*).
2. **İz** — aynı iz görülmeye devam ediyor, tanınmasa bile: sahip hâlâ orada.
3. **Taşıma** — yüz hiç görünmüyor ama sahne boşalmadı (gövde var): `carryLimit` (10 dk) kadar.

Çapa koptuktan sonra aynı yerde (IoU ≥ 0,2) 1,5 sn içinde beliren yüz, sahibin devamı sayılır
(el yüzü kapatır, kafa bir an kadrajdan çıkar).

**Okunabilirlik ilkesi:** *Okunamayan yüzden kimlik kararı çıkarılmaz.* Dik açılı (|yaw| > 0,70,
|pitch| > 0,50 rad) ya da kalitesi 0,15 altı yüz ne "sahip" ne "yabancı"dır. Sahibin izinde
okunamayan bir yüz çapayı sürdürür; **okunabilir** ve kesin yabancı (skor < reject) bir yüz ise
çapayı düşürür ve tehdit sayılır (koltuk el değiştirme senaryosu).

**Güvenlik dengesi:**
- Düşük (sürdürme) eşiği artık **yalnızca sahibin izindeki** yüze uygulanır. Çapa uzun yaşadığı
  için bunu tüm yüzlere açmak, 0,55–0,70 arası skorlayan bir yabancıyı "sahip" sayardı.
- Çapa canlıyken kadrajdaki gövde/kişi sahibin kendisidir: T2 (yüzsüz kişi) tetiklenmez ve
  fotoğraf çekilmez.
- Yabancı yüz tetikleyicisi (T1), kapak, hareket, kamera ve girdi tetikleyicileri aynen durur;
  çapa yalnızca "sahip burada mı" sorusunu yanıtlar.
- Artık kalan risk: sahne hiç boşalmadan koltuğun el değiştirmesi *ve* yeni kişinin yüzünü hiç
  okunabilir göstermemesi. `carryLimit` bunu 10 dakikayla sınırlar.

**Doğrulama:** `swift run nobetci-eval presence 30` — sahip okunmayan karelerde iz/gövde
kapsamasını ve poz dağılımını ölçer; okunabilirlik eşikleri bu çıktıyla kalibre edilir.


## 19. "Sahne boş sanılması" — çapanın ikinci katmanı (2026-10-21)

§18'deki çapa yerinde olmasına rağmen cihazda beş yanlış alarm daha yaşandı (17:04–17:06):
yan ekrana bakarken (*kilit: girdi*), masada bir şeye uzanırken (*kadrajda*), saçını
düzeltirken (*kilit: kamera kaydı*), yüzünü kaşırken (*kadrajda*).

**Ölçüm:** `nobetci-eval presence 30` — sahip tanınmayan karelerin **%0'ında** gövde
bulundu; %62'sinde ne yüz ne gövde vardı. Yani yakın oturan kullanıcıda
`VNDetectHumanRectanglesRequest` hiç tetiklenmiyor.

**Kök neden (ikinci katman):** Yüz dedektörü profil/örtülü/aşağı bakan yüzü kaçırınca ve
gövde dedektörü de susunca `anyPerson = false` oluyor; sistem sahneyi **boş** sanıyor.
Bu tek yanlış çıkarım üç ayrı arızaya yol açıyordu:
1. Çapa taşınamıyor → varlık düşüyor → girdi kilitliyor (T3).
2. Sahip "kadrajdaki yabancı" sayılıp fotoğraflanıyor.
3. Boş sanılan sahnedeki büyük görüntü değişimi "kamera oynatıldı" (T8) okunuyor — elin
   saçına gitmesi kilit sebebi oluyordu.

**Çözüm:** `VNGeneratePersonSegmentationRequest` (`.fast`) ile **kişi maskesi**. Maske
insanı yöne bakmadan görür. Yalnızca (a) hiç yüz bulunamadığında ve (b) taşınacak canlı
bir çapa varken hesaplanır — sahip gerçekten yokken bedeli sıfırdır.

- **Bölgeyle sınırlı bakılır** (`PersonMask.ownerRegion`): soru "kadrajda biri var mı"
  değil, "**sahibin durduğu yerde** hâlâ biri var mı"dır. Sandalyeye asılı bir mont ya da
  arkadan geçen biri çapayı yaşatmaz. Eşik: bölgede %20 kişi pikseli.
- **Tek yüz evlat edinme** (`canAdoptSoleFace`): masada bir şeye uzanırken kutu çok kayar,
  IoU tutmaz. Kadrajda tek yüz varsa ve sahne boşalmadıysa o yüz sahibin devamı sayılır —
  tanıma yerine geçmez, yalnızca varlığı sürdürür.
- **T8 bastırma:** çapa canlıyken kadrajdaki değişim sahibin kendi hareketidir.

**Güvenlik:** Maske yalnızca *var olan* bir çapayı taşır; varlık kurmaz. Okunabilir ve kesin
yabancı bir yüz çapayı düşürür. Taşıma `carryLimit` (10 dk) ile sınırlıdır. Sahip
kadrajdan çıkıp bölgesi boşalınca çapa 1,5 sn içinde ölür.

**Kalibrasyon:** `nobetci-eval presence` çıktısındaki "KİŞİ MASKESİ" bölümü bölge oranının
dağılımını verir; %20 eşiği bununla doğrulanır.


## 20. Karanlıkta tanımama — pozlama ve uyarlanan profil (2026-10-21)

**Belirti:** Karanlık odada, arkada parlak monitör varken sahip tanınmadı; "kadrajda"
etiketiyle kendi fotoğrafı çekildi (17:16). Önceki iki katmandan farklı: burada yüz
**görülüyor**, **tanınmıyor**.

**Kök neden:** Kamera pozlaması parlak ekrana göre ayarlanınca yüz koyu kalıyor. Gömme
vektörü, gündüz kaydedilmiş profille eşleşmiyor (skor sürdürme eşiğinin altında). Çapa bu
boşluğu kapatamaz: çapa varlığı *sürdürür*, **kuramaz** — kurmak yalnızca tanımayla olur
(güvenlik gereği).

**Çözüm iki katmanlı:**

1. **Pozlama normalleştirme** (`ExposureNormalizer`): hizalanmış kesit, gömmeden önce sabit
   bir luma ortalaması (0,45) ve kontrastına (std 0,22) çekilir. Kazanç 4× ile sınırlıdır;
   düz/karanlık kesitte gürültü yüz gibi görünmesin. `FaceCrop` tek hat olduğu için kayıt,
   çalışma anı ve değerlendirme aynı işlemden geçer.
2. **Uyarlanan profil**: şifre doğru girildiğinde kimlik kanıtlanmıştır; o anki yüz vektörü
   profile eklenir (Face ID'nin yaklaşımı). Böylece yeni ışık, gözlük ya da saç bir kez
   şifreyle açılınca kalıcı olarak öğrenilir.
   - Yalnızca kadrajda **tek** ve **okunabilir** yüz varken, kalite ≥ 0,2 ise aday alınır
     (yanındaki biri ya da kötü açılı kare profile yazılmasın).
   - Ayrı dosyada (`profile-adaptive.bin`), en fazla 20 vektör (FIFO). Kayıt profili
     (`profile.bin`) bozulmaz; "yüz profilini yenile" öğrenilenleri sıfırlar.
   - Öğrenilen vektör sonraki nöbet beklenmeden devreye girer.

**Sessiz uyumsuzluğa karşı:** `FaceCrop.pipelineVersion` eklendi. Ön işleme değişince eski
sürümle kaydedilmiş profil birebir uyumlu değildir; menüde "Yüz tanıma iyileştirildi —
Ayarlar'dan profili yenile" uyarısı çıkar. Profil/çalışma-anı uyumsuzluğu bu projede bir kez
sessizce "hiç tanımıyor" hatasına yol açmıştı; bir daha sessiz kalmıyor.
