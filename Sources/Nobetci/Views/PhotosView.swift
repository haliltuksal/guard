import SwiftUI
import NobetciCore

/// Fotoğraf galerisi: sen yokken kadraja girenlerin görüntüleri.
/// İki yerden açılır — menüdeki "Fotoğraflar" düğmesi (tümü) ve döndüğünde
/// kendiliğinden (`headline` dolu: yalnızca o nöbette yenileri).
struct PhotosView: View {
    let model: AppModel
    var headline: String?
    var onClose: () -> Void = {}

    @State private var items: [(ref: SnapshotRef, image: NSImage)]
    @State private var zoomed: SnapshotRef?
    @State private var confirmingDeleteAll = false

    init(model: AppModel,
         photos: [(ref: SnapshotRef, image: NSImage)],
         headline: String? = nil,
         onClose: @escaping () -> Void = {}) {
        self.model = model
        self.headline = headline
        self.onClose = onClose
        _items = State(initialValue: photos)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let headline {
                Label(headline, systemImage: "person.fill.viewfinder")
                    .font(.headline).foregroundStyle(.orange)
                    .padding(.horizontal).padding(.bottom, 4)
            }
            if items.isEmpty { empty } else { grid }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 540)
        .overlay { if let zoomed, let item = items.first(where: { $0.ref.id == zoomed.id }) { zoomView(item) } }
    }

    // MARK: Parçalar

    private var header: some View {
        HStack {
            Text(L10n.t("photos.title")).font(.title2.weight(.semibold))
            Spacer()
            Button(L10n.t("report.close"), action: onClose).keyboardShortcut(.escape, modifiers: [])
        }.padding()
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(L10n.t("photos.empty")).font(.headline)
            Text(L10n.t("photos.empty.hint")).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items, id: \.ref.id) { item in cell(item) }
            }
            .padding(.horizontal).padding(.bottom, 12)
        }
    }

    private func cell(_ item: (ref: SnapshotRef, image: NSImage)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(nsImage: item.image)
                .resizable().aspectRatio(4.0 / 3.0, contentMode: .fill)
                .frame(height: 118).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) { badge(item.ref.reason) }
            Text(item.ref.at, format: .dateTime.day().month().hour().minute().second())
                .font(.caption).monospacedDigit()
            Text(Labels.snapshot(item.ref.reason)).font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { zoomed = item.ref }
        .contextMenu {
            Button(L10n.t("photos.delete.one"), role: .destructive) { delete(item.ref.id) }
        }
        .help(L10n.t("photos.zoom.hint"))
    }

    /// Kilit sebebiyle çekilenler göze çarpsın (yalnız "kadrajda" olanlardan ayırt edilir).
    @ViewBuilder
    private func badge(_ reason: SnapshotReason) -> some View {
        if reason != .personSeen {
            Image(systemName: reason == .wrongPasscode ? "xmark.shield.fill" : "lock.fill")
                .font(.caption2).padding(4)
                .background(.orange, in: Circle())
                .foregroundStyle(.white)
                .padding(5)
        }
    }

    private var footer: some View {
        HStack {
            Text(Labels.retention(days: model.currentSettings().snapshotRetentionDays))
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if !items.isEmpty {
                Button(L10n.t("photos.delete.all"), role: .destructive) { confirmingDeleteAll = true }
                    .confirmationDialog(L10n.t("photos.delete.all.confirm"), isPresented: $confirmingDeleteAll) {
                        Button(L10n.t("photos.delete.all"), role: .destructive) {
                            _ = model.deleteAllSnapshots()
                            items.removeAll()
                        }
                    }
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func zoomView(_ item: (ref: SnapshotRef, image: NSImage)) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.75)).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(nsImage: item.image)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(item.ref.at, format: .dateTime.day().month().hour().minute().second())
                    .font(.callout).monospacedDigit().foregroundStyle(.white)
                Text(Labels.snapshot(item.ref.reason)).font(.caption).foregroundStyle(.white.opacity(0.8))
                HStack {
                    Button(L10n.t("photos.close.zoom")) { zoomed = nil }
                    Button(L10n.t("photos.delete.one"), role: .destructive) { delete(item.ref.id); zoomed = nil }
                }
            }
            .padding(20)
        }
        .onTapGesture { zoomed = nil }
    }

    private func delete(_ id: String) {
        model.deleteSnapshot(id: id)
        items.removeAll { $0.ref.id == id }
    }
}
