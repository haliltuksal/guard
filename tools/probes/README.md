# Doğrulama deneyleri

Tasarım aşamasında (2026-10-20) kritik teknik varsayımları ölçmek için yazılmış, atılacak deney kodlarıdır.
Ürün kodu değildir. Sonuçları ve kanıt eşlemesi: `docs/superpowers/specs/2026-10-20-nobetci-design.md` §15.1.

| Dosya | Ne ölçer | Bulgu |
|---|---|---|
| `lid.swift` | Kapak açısı sensörünün root olmadan okunması | V2 |
| `accel.swift` | İvmeölçerin root olmadan okunması | V3 |
| `idle.swift` | "Aktif gösterme" yöntemlerinin boşta kalma sayaçlarına etkisi | V6, V7 |
| `idlewatch.swift` | Boşta kalma sayaçlarını saniye saniye izleme | (yardımcı) |
| `swiftpm-clt/` | Xcode olmadan SwiftUI menü çubuğu uygulaması + Swift Testing | V8, V9 |
| `coreml/` | PyTorch → Core ML dönüşümü ve çalışma anında derleme | V10 |

Çalıştırma: `swift lid.swift` (ve diğerleri). `idle.swift` çalışırken klavye ve fareye dokunulmamalıdır.
`swiftpm-clt` testleri için §15.1 V9'daki bayraklar gerekir.
