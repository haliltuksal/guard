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
                Text(L10n.t("report.photos", "\(photos.count)"))
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
                                Text(Labels.snapshot(item.ref.reason)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.horizontal)
                }
            }

            Divider().padding(.vertical, 8)
            List(Array(session.events.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 12) {
                    Image(systemName: Labels.icon(for: event.kind)).foregroundStyle(Labels.color(for: event.kind))
                    Text(event.at, format: .dateTime.hour().minute().second())
                        .monospacedDigit().foregroundStyle(.secondary)
                    Text(Labels.event(event.kind))
                }
            }
        }
        .frame(width: 460, height: 420)
    }

}
