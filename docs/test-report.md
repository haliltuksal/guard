# Nöbetçi — Doğrulama Raporu

| | |
|---|---|
| Tarih | 2026-10-21 |
| Dal | `feature/v1` |
| Otomatik testler | **77 geçti** (`make test`) |
| `NobetciCore` satır kapsamı | **%94,5** (kapı ≥ %90, `make coverage`) |

Bu rapor neyin **otomatik doğrulandığını** ve neyin **cihazda (senin Mac'inde,
izinler + gözle)** doğrulanacağını ayırır. Cihaz gerektiren maddeler, izin
verip uygulamayı çalıştırınca birlikte yürütülecek.

## 1. Otomatik doğrulanan (bu derlemede)

- Çekirdek durum makinesi ve 14 tetikleyici, yüz/şifre kilit açma, dönüş davranışı,
  uyku, açılış oturumu (63 çekirdek testi).
- Türkçe Q klavye çözümü: ölü tuş (`^`+`e`→`ê`), Option karakterleri (`₺`,`€`).
- Girdi politikası kararları; kalkan pencere kümesi ekran kümesini izliyor.
- Şifre PBKDF2 + sabit zamanlı karşılaştırma; katlanan bekleme yalnızca monoton saat.
- Şifreli dosya deposu: round-trip, diskte düz metin yok, ayar oynanırsa varsayılana dönüş.
- Yüz hizalama benzerlik dönüşümü; hareket/doku/parlaklık metrikleri; IoU iz takibi.
- **Yüz modeli (Faz 2):** FaceNet → Core ML, eşitlik **0,999907**, Neural Engine
  **~0,9 ms/çıkarım**, 45 MB (`docs/model-evaluation.md`).

Önceki ortam doğrulamaları V1–V16: `docs/superpowers/specs/2026-10-20-nobetci-design.md` §15.1.

## 2. Cihazda doğrulanacak (izin + gözle)

| # | Konu | Nasıl | Durum |
|---|---|---|---|
| D3 | ~~Sahte etkinlik~~ | Özellik etik gerekçeyle çıkarıldı | İptal |
| D4 | Uyku/ekran koruyucu/otomatik kilit engelleme | 15 dk nöbet; `pmset -g assertions` yalnızca uyku bildirimleri, `UserIsActive` yok | Bekliyor |
| D5 | Kalkanın her şeyi örtmesi | Spotlight/tam ekran/bildirim/Mission Control/harici ekran | Bekliyor |
| D6 | Blur okunamazlık | `docs/test-assets/legibility.html` arkada, `screencapture`; 12–72 pt okunmamalı | Bekliyor |
| D7 | Girdi engelleme matrisi | Cmd+Tab, Cmd+Space, Cmd+Opt+Esc, Cmd+Q, F3, Launchpad, ekran görüntüsü, köşeler, Fn, dikte, harici klavye/fare; Terminal "Güvenli Klavye Girişi" açıkken tekrar; başka süreçten `CGEventPostToPid` | Bekliyor |
| D8 | Accessory'de kiosk (Cmd+Tab/Force Quit kapalı) | Kilitliyken dene | Bekliyor |
| D9 | Kilitlenince öne geçme | Başka uygulama öndeyken kilit | Bekliyor |
| D10 | launchd `kill -9` → ≤ 2 sn kilitli açılış | Arka arkaya iki kez; süre ölç | Bekliyor |
| D11 | İmza + TCC izin kalıcılığı | `make cert` sonrası yeniden derle-kur, izinler kalmalı | **`make cert` gerekiyor (anahtar zinciri parolası)** |
| D12 | Center Stage kapatma / efekt uyarısı | Kamera açıkken | Bekliyor |
| D13 | Göz kırpma güvenilirliği | 50 gerçek kırpma; tanılama paneli | Bekliyor |
| D14 | LFW eşik kalibrasyonu | `nobetci-eval` + LFW (hizalama hattı hazır); `accept/sustain/reject` yeniden seçilir | Başlangıç eşikleri kullanımda |
| D15 | Performans bütçeleri | 30 dk; boş sahne CPU < %5, bellek < 300 MB, çıkarım ≤ 10 ms (NE 0,9 ms ✅) | Kısmi (gecikme ✅) |
| D16 | Ağ trafiği olmaması | `lsof -i -a -p <pid>` boş | Bekliyor (kod: ağ API'si yok) |
| D17 | Ekran/HID/USB/güç bildirimleri | Tak-çıkar | Bekliyor |
| D18 | Şifrede Türkçe düzen/Option/ölü tuş (kalkanda uçtan uca) | Kilitliyken yaz | Ön doğrulama ✅ (V15); kalkanda bekliyor |
| D20 | Sesli Denetim tespiti | Ayarı açıp kapat | Bekliyor |
| D21 | macOS 14/15 uyumu | İkinci bir Mac'te (macOS 14/15) kabul alt kümesi | Bekliyor |

## 3. Kabul testleri (spec §13.4) — cihazda

1. T1–T14 tetikleyicileri, tepki süreleriyle.
2. Girdi engelleme matrisi (D7).
3. Kalkan kapsaması (D5) ve okunamazlık (D6).
4. Kilit açma: sahip ≥ %98 başarı (3 ışık, gözlüklü/gözlüksüz); basılı fotoğraf ve
   telefon ekranıyla açılmamalı; sıkı modda göz kırpan videoyla da açılmamalı.
5. Şifre: Türkçe karakterler, ölü tuş, Option; bekleme süreleri; yeniden başlatmada sayaç.
6. Uyku engelleme (D4): Slack/Teams **"boşta" göstermeli** (doğru davranış), uyku/kilit olmamalı.
7. Yaşam döngüsü: `kill -9` (D10), uyku/uyanma, yeniden başlatma → Kapalı, tek kopya.
8. İmza (D11); başka Mac'te "Yine de Aç".
9. Gizlilik: `lsof` ağ yok (D16); diskte şifresiz yüz verisi yok (otomatik ✅).
10. Performans (D15).

Her satır çalıştırıldığında ölçümüyle buraya yazılacak.

## 4. Bilinen sınırlar

- Derinlik sensörü yok: kararlı bir fotoğraf/video saldırısı varsayılan modda teorik
  olarak mümkün; sıkı mod zorlaştırır. Bu bir gizlilik kalkanıdır.
- Model ağırlıkları ticari olmayan lisanslı (hedef kitle B — ücretsiz paylaşım için uygun).

## 5. İkinci inceleme (2026-10-21, taze gözle) — bulundu ve düzeltildi

| # | Bulgu | Etki | Düzeltme |
|---|---|---|---|
| R1 | **Karışık zaman tabanı**: kamera PTS (mach_absolute) motor saatiyle (mach_continuous) karışıyordu → uyumuş Mac'te sahip saatlerce "var" (fail-open) | Kritik | Kareler motor saatiyle damgalanır (`AppModel` onFrame) |
| R2 | Kamera örtülüyken varlık düşmüyordu (özet yok, `.covered` present'ta yutuluyor) → örtüp uzaklaş = kilitsiz | Önemli | `handleCamera(.present,.covered)` varlığı 1,5 sn'de düşürür → T6 (test: `coveredCameraWhilePresentDecaysPresenceThenLocks`) |
| R3 | Watchdog kamera ısınmasında (0,5–2 s) sahte `cameraLost` kilidi | Önemli | İlk kare görülmeden "durdu" denmez; 10 s başlangıç toleransı |
| R4 | Parlak düz duvar "örtülü" sayılıyordu (`texture<0.02` tek başına) → sürekli T6 | Önemli | Doku çöküşü yalnızca loşken (`brightness<0.3`) örtülü sayılır (test güncellendi) |
| R5 | Yüz kaydı bitişinde `stopRunning` delegate kuyruğundan → deadlock riski | Önemli | Ana kuyruğa atılır |
| R6 | Ayar değişimi yeni motorda `bootSession=""` → çökme-kurtarma (T13) bozuluyordu | Önemli | Yeniden tohumlanır |
| R7 | Girdi filtresi kurulamazsa sessizce "nöbette" (fail-open) | Önemli | Hata → T14 kilit |
| R8 | Oturumlar yalnızca elle durdurunca kaydediliyordu | Orta | `stopSensors`'ta her bitişte yazılır; relaunch oturumu da tutulur |
| R9–R11 | Kamera ✓ hiç yanmıyordu; pipeline/kamera nöbetler arası sızıyordu; kurulum açılışta değil menüye tıklayınca geliyordu | Küçük | Düzeltildi |

79 test yeşil. Doğru olduğu yeniden izlenen: durum geçişleri, T1 debounce, histerezis, monoton bekleme, kripto, girdi sızmazlığı, hizalama, seri olay kanalı.

## 6. Cihazda ilk sonuçlar (2026-10-21, gece, Halil'in Mac'i)

| Konu | Sonuç |
|---|---|
| Yüz tanıma (canlı, FaceCrop hattı) | 282/282 kare "sahip", skor ort. 0,90, min 0,71 ✅ |
| D13 canlılık (göz kırpma, EAR) | 10 sn'de **3 kırpma**; EAR açık ≈0,26 / kapalı ≈0,08 ✅ |
| Yüzle kilit açma | Çalışıyor (02:21:47 "Yüzle açıldı") ✅ |
| Kamera ısınması | İlk ~9 kare siyah (parlaklık 0,000) → T6 süreklilik kapısı (≥0,5 sn) eklendi |
| Kafa çevirme | 12/263 kare <0,70 → iz sürekliliği: sahip izi tehdit değil |
| Kadraja geri giriş | 0,1 sn'de "yabancı yüz" → T1 iz-başına 0,5 sn kabul süresi (spec) |
| Gece odası | parlaklık 0,29, doku 0,04 → "loş" eşiği 0,2, doku 0,01 (örtülü değil) |
| Dönüş davranışı | Kullanıcı kararı: varsayılan **nöbet sürsün**; durdurma = "Buradayım" |
| Yabancı yüzde blur gecikmesi | Kullanıcı: "biraz geç". Zincir: durgun sahnede 0,5 sn analiz aralığı + 0,5 sn belirsiz kabul + motor 3 kare. → Kişi görünür görünmez her kare analiz; kabul 0,3 sn; motor 2 kare; yüz varken gövde taraması atlanır (kare başı süre ↓). Ölçülecek. |
| Bütünsel bakış (2026-10-21) | Uyarı 0. Ertelenen küçükler kapatıldı: #8 lockout→Keychain, #10 düzen tazeleme, #12 PBKDF2 kalibrasyon, #13 kabul-seviyesi pencere. Kalan: #11 kesilen oturum raporu (düşük). |
