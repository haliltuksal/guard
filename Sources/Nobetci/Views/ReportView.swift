import SwiftUI
import NobetciCore

/// "Sen yokken olanlar" raporu: özet, olay zaman çizelgesi ve çekilen fotoğraflar.
struct ReportView: View {
    let session: SessionRecord
    var photos: [(ref: SnapshotRef, image: NSImage)] = []
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("report.title")).font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.t("report.close"), action: onClose)
            }.padding()
            Text(ReportBuilder.summary(session))
                .font(.headline).foregroundStyle(.secondary)
                .padding(.horizontal)

            if !photos.isEmpty {
                Text("Kimler yaklaştı (\(photos.count))")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal).padding(.top, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(photos, id: \.ref.id) { item in
                            VStack(spacing: 4) {
                                Image(nsImage: item.image)
                                    .resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 132, height: 99).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(item.ref.at, format: .dateTime.hour().minute().second())
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                Text(label(item.ref.reason)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.horizontal)
                }
            }

            Divider().padding(.vertical, 8)
            List(Array(session.events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: event.kind)).foregroundStyle(color(for: event.kind))
                    Text(event.at, format: .dateTime.hour().minute().second())
                        .monospacedDigit().foregroundStyle(.secondary)
                    Text(describe(event.kind))
                }
            }
        }
        .frame(width: 460, height: 420)
    }

    private func label(_ reason: SnapshotReason) -> String {
        switch reason {
        case .personSeen: "kadrajda"
        case .locked(let r): "kilit: \(self.reason(r))"
        case .wrongPasscode: "yanlış şifre"
        }
    }

    private func describe(_ kind: GuardLogKind) -> String {
        switch kind {
        case .guardStarted: "Nöbet başladı"
        case .guardEnded: "Nöbet bitti"
        case .ownerLeft: "Sahip ayrıldı"
        case .ownerReturned: "Sahip döndü"
        case .triggered(let r): "Kilit: \(reason(r))"
        case .unlockedByFace: "Yüzle açıldı"
        case .unlockedByPasscode: "Şifreyle açıldı"
        case .wrongPasscode: "Yanlış şifre"
        case .sensorIssue(let s): "Sensör sorunu: \(s)"
        case .cameraIssue(let s): "Kamera sorunu: \(s)"
        case .relaunched: "Yeniden başlatıldı"
        case .slept: "Uyudu"
        case .woke: "Uyandı"
        case .endedByRestart: "Yeniden başlatmayla bitti"
        }
    }

    private func reason(_ r: LockReason) -> String {
        switch r {
        case .strangerFace: "yabancı yüz"
        case .facelessPerson: "yüzsüz kişi"
        case .input: "girdi"
        case .lidAngle: "kapak açısı"
        case .motion: "hareket"
        case .cameraCovered: "kamera örtüldü"
        case .cameraLost: "kamera kesildi"
        case .cameraShift: "kamera kaydı"
        case .display: "ekran"
        case .usb: "USB"
        case .power: "güç"
        case .sleep: "uyku"
        case .relaunch: "yeniden başlatma"
        case .filterLost: "girdi filtresi"
        }
    }

    private func icon(for kind: GuardLogKind) -> String {
        switch kind {
        case .triggered: "lock.fill"
        case .wrongPasscode: "xmark.shield"
        case .unlockedByFace, .unlockedByPasscode: "lock.open.fill"
        default: "circle.fill"
        }
    }

    private func color(for kind: GuardLogKind) -> Color {
        switch kind {
        case .triggered, .wrongPasscode: .orange
        case .unlockedByFace, .unlockedByPasscode: .green
        default: .secondary
        }
    }
}
