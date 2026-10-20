# Nöbetçi

Masandan kalktığında Mac'ini uyanık tutan, yabancı biri yaklaşınca ya da
müdahale olunca ekranı anında bulanıklaştırıp girdileri kapatan ve yalnızca
**senin yüzünle** (canlılık kontrolüyle) ya da **uygulama şifrenle** açılan
menü çubuğu uygulaması. Tümü cihazda; internet yok.

## Tasarım

- Tasarım: `docs/superpowers/specs/2026-10-20-nobetci-design.md`
- Uygulama planı: `docs/superpowers/plans/2026-10-20-nobetci-implementation.md`
- Model değerlendirmesi: `docs/model-evaluation.md`
- Doğrulama raporu: `docs/test-report.md`

## Mimari

| Katman | Sorumluluk |
|---|---|
| `NobetciCore` | Saf durum makinesi ve tüm kararlar (donanıma dokunmaz, tam test edilir) |
| `NobetciVision` | Kamera karesi → `FrameSummary` (Vision + Core ML yüz tanıma) |
| `NobetciSystem` | macOS adaptörleri (sensörler, girdi filtresi, kalkan, güç, launchd, Keychain) |
| `Nobetci` | SwiftUI arayüz + tüm parçaları bağlayan `AppModel`/`EffectRunner` |

## Geliştirme (Xcode gerekmez)

```
make model     # yüz modelini indirip Core ML'e çevirir (bir kez; eşitlik kapılı)
make test      # tüm testler (Swift Testing)
make coverage  # NobetciCore satır kapsamı ≥ %90 kapısı
make cert      # kendinden imzalı kod imzalama kimliği (bir kez; anahtar zinciri parolası)
make app       # build/Nöbetçi.app (imzalı)
make dist      # build/Nöbetçi-<sürüm>.dmg
make install   # /Applications'a kurar
```

## İlkeler

- Üçüncü parti çalışma zamanı bağımlılığı yok (yalnızca Apple framework'leri).
- Ağ kodu yok; hiçbir veri cihazdan çıkmaz.
- Fotoğraf çekme ve "aktif görünme" (Slack/Teams'i kandırma) **yok** — bilinçli.
- Fail-closed: emin olunamayan her durumda kilitlenir.
