import SwiftUI
import NobetciCore

/// Menü çubuğu paneli: durum, "Uzaktayım"/"Korumayı kapat", nöbette sensör durumları.
struct MenuView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nöbetçi").font(.headline)
                Spacer()
                Text(statusText).font(.subheadline).foregroundStyle(.secondary)
            }

            if !model.prepareProblems.isEmpty, case .off = model.state {
                ForEach(model.prepareProblems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }

            Button(action: { model.toggleGuard() }) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            if model.profileNeedsRefresh {
                Label(L10n.t("menu.profile.stale"), systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
            }

            if case .guarding = model.state { sensorRow }

            Divider()
            Button(action: { model.openPhotoGallery() }) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(L10n.t("menu.photos"))
                    Spacer()
                    if model.photoCount > 0 {
                        Text("\(model.photoCount)")
                            .font(.caption).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.callout)

            Divider()
            HStack {
                Button(L10n.t("menu.settings.open")) { openSettings() }
                Spacer()
                Button(L10n.t("menu.quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    private var sensorRow: some View {
        HStack(spacing: 14) {
            sensorDot(L10n.t("menu.sensor.camera"), model.sensorStatus.camera)
            sensorDot(L10n.t("menu.sensor.lid"), model.sensorStatus.lid)
            sensorDot(L10n.t("menu.sensor.accel"), model.sensorStatus.accelerometer)
            sensorDot(L10n.t("menu.sensor.wake"), model.sensorStatus.wakeKeep)
        }
        .font(.caption2)
    }

    private func sensorDot(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? .green : .secondary)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch model.state {
        case .off: L10n.t("menu.status.ready")
        case .preparing: L10n.t("menu.status.preparing")
        case .guarding: L10n.t("menu.status.guarding", "")
        case .locked: L10n.t("shield.searching")
        }
    }

    private var buttonTitle: String {
        if case .guarding = model.state { return L10n.t("menu.stop") }
        return L10n.t("menu.away")
    }

    private var isBusy: Bool {
        switch model.state { case .preparing, .locked: true; default: false }
    }
}
