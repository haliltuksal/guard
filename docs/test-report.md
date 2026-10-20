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
| D21 | macOS 14/15 uyumu | Fatih'in Mac'inde kabul alt kümesi | Bekliyor |

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
