# Yüz Modeli Değerlendirmesi

| | |
|---|---|
| Tarih | 2026-10-21 |
| Durum | 2.1 tamam (model + eşitlik + gecikme); 2.2 (LFW eşik kalibrasyonu) Faz 4 sonrası |

## Seçilen model (başlangıç)

| Özellik | Değer |
|---|---|
| Model | FaceNet · InceptionResnetV1 (facenet-pytorch) |
| Ağırlık | VGGFace2 ön-eğitimli; kod lisansı MIT |
| Ağırlık SHA-256 | `281cebca8662831adb987a874bdcb36e73f5b1c6dc5ee5878f305e985625d99b` |
| Gömme boyutu | 512 (L2-normalize) |
| Girdi | 160×160 RGB |
| Core ML | mlprogram, FP16, macOS 14+ |
| Paket boyutu | 45 MB (≤ 150 MB bütçe) |
| Dönüşüm yolu | `torch.export` → `run_decompositions({})` → coremltools 9 (trace yolu torch 2.14 + ct 9'da bu modeli çeviremedi) |
| **Eşitlik** (torch↔CoreML) | **kosinüs 0.999907** (100 rastgele girdi; kapı ≥ 0.999) ✅ |
| **Gecikme** (Neural Engine) | **~0.9 ms/çıkarım** (kapı ≤ 10 ms) ✅ — `MLModel.compileModel` ile çalışma anında derlenip ölçüldü |

`make model` → `build/Model.mlpackage` üretir (eşitlik kapılı). Paket git'e girmez (.gitignore); `make model` ile yeniden üretilir. Uygulama ilk açılışta `.mlpackage`'ı `MLModel.compileModel` ile derler (V10; Xcode/coremlcompiler gerekmez).

## Başlangıç (provisional) eşikleri

Kosinüs (L2-normalize gömme) üzerinde, FaceNet/VGGFace2'nin yayımlanmış LFW karakteristiğine (~%99,65 doğruluk) dayanan **başlangıç** değerleri:

| Eşik | Değer | Anlamı |
|---|---|---|
| `accept` (`T_kabul`) | 0.70 | ilk tanıma ve kilit açma |
| `sustain` (`T_sürdür`) | 0.55 | doğrulanmış izi sürdürme (histerezis) |
| `reject` (`T_red`) | 0.40 | kesin yabancı |

> ⚠️ Bunlar başlangıç değerleridir. **Kesin kalibrasyon (D14)** Faz 4 (üretim hizalama hattı: Vision tespiti → 5 nokta → 112/160 hizalama → Core ML) tamamlandıktan sonra, `nobetci-eval` ile LFW üzerinde yapılacak: TAR@FAR = 1e-3/1e-4/1e-5 ölçülüp spec §6.8-5 kuralına göre `accept` = tek kare FAR ≤ 1e-4, `sustain` = FAR ≤ 1e-3, `reject` = sahibin gerçek koşul kayıtlarında FRR ≤ 1e-3 veren değerler seçilecek. Sonuçlar buraya yazılacak.

## Aday karşılaştırması (D14, Faz 4 sonrası)

Spec §6.8 adayları: FaceNet (bu), ArcFace IResNet-50/100, AdaFace IR-50/101. Seçim kuralı: NE'de ≤ 10 ms ve ≤ 150 MB koşuluyla TAR@FAR=1e-4 en yüksek aday. FaceNet başlangıç modelidir; aligner hazır olunca üçü de aynı hatla ölçülüp nihai seçim yapılacak.
