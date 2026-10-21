import SwiftUI
import NobetciCore

/// Ayarlar penceresi (spec §8.5). Korumayı zayıflatan değişiklikler uygulama
/// açıkken kaydedilir; şifre onayı ve hassas işlemler cihazda eklenecek.
struct SettingsView: View {
    let model: AppModel
    @State private var settings: GuardSettings
    @State private var confirmUninstall = false
    @State private var reenrolling = false
    @State private var reenrollCount = 0
    @State private var reenrollTarget = 50
    @State private var reenrollDone: Bool?
    @State private var deletedPhotos: Int?

    init(model: AppModel) {
        self.model = model
        _settings = State(initialValue: model.currentSettings())
    }

    var body: some View {
        TabView {
            general.tabItem { Label(L10n.t("settings.general"), systemImage: "gear") }
            detection.tabItem { Label(L10n.t("settings.detection"), systemImage: "sensor") }
            photos.tabItem { Label(L10n.t("settings.photos"), systemImage: "photo") }
            unlock.tabItem { Label(L10n.t("settings.unlock"), systemImage: "faceid") }
            about.tabItem { Label(L10n.t("settings.about"), systemImage: "info.circle") }
        }
        .frame(width: 440, height: 320)
        .onChange(of: settings) { _, new in model.update(new) }
    }

    private var general: some View {
        Form {
            Toggle("Girişte başlat", isOn: $settings.startAtLogin)
            Picker("Dönüş davranışı", selection: $settings.returnBehavior) {
                Text("Nöbet kapansın").tag(ReturnBehavior.closeGuard)
                Text("Nöbet sürsün").tag(ReturnBehavior.keepGuarding)
            }
            LabeledContent("Kısayol", value: "⌃⌥⌘L")
        }.padding()
    }

    private var detection: some View {
        Form {
            Picker("Mesafe", selection: $settings.distance) {
                Text("Yakın").tag(DistanceSensitivity.near)
                Text("Orta").tag(DistanceSensitivity.medium)
                Text("Uzak").tag(DistanceSensitivity.far)
            }
            sensitivityPicker("Kapak", $settings.lid)
            sensitivityPicker("Hareket", $settings.motion)
            Toggle("Yüzsüz kişi algılama", isOn: $settings.facelessDetection)
            Toggle("Kamera kayması algılama", isOn: $settings.cameraShiftDetection)
            Toggle("Ekran tetikleyici", isOn: $settings.displayTrigger)
            Toggle("USB tetikleyici", isOn: $settings.usbTrigger)
            Toggle("Güç kaynağı tetikleyici", isOn: $settings.powerTrigger)
        }.padding()
    }

    private var photos: some View {
        Form {
            Toggle("Sen yokken yaklaşanların fotoğrafını çek", isOn: $settings.captureSnapshots)
            Picker("Saklama süresi", selection: $settings.snapshotRetentionDays) {
                Text("7 gün").tag(7); Text("30 gün").tag(30); Text("90 gün").tag(90)
            }
            Text("Fotoğraflar şifrelenir ve yalnızca bu Mac'te kalır; internete gönderilmez.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Tüm fotoğrafları sil", role: .destructive) { deletedPhotos = model.deleteAllSnapshots() }
            if let deletedPhotos {
                Text("\(deletedPhotos) fotoğraf silindi.").font(.footnote).foregroundStyle(.secondary)
            }
        }.padding()
    }

    private var unlock: some View {
        Form {
            Toggle("Göz kırpma iste (fotoğrafla kandırmayı zorlaştırır)", isOn: $settings.requireBlink)
            Toggle("Sıkı mod (baş hareketi iste)", isOn: $settings.strictMode)
            Section("Yüz profili") {
                if reenrolling {
                    ProgressView(value: Double(reenrollCount), total: Double(reenrollTarget))
                    Text("\(reenrollCount) / \(reenrollTarget) — kameraya bak, başını yavaşça çevir")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Yüz profilini yenile") { startReenroll() }
                    if let done = reenrollDone {
                        Text(done ? "Profil yenilendi." : "Yenileme başarısız — kamera iznini kontrol et.")
                            .font(.footnote).foregroundStyle(done ? .green : .red)
                    }
                }
            }
        }.padding()
    }

    private func startReenroll() {
        reenrolling = true; reenrollCount = 0; reenrollDone = nil
        model.reenrollFace(
            onProgress: { count, total in Task { @MainActor in reenrollCount = count; reenrollTarget = total } },
            onComplete: { ok in Task { @MainActor in reenrolling = false; reenrollDone = ok } })
    }

    private var about: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield").font(.largeTitle)
            Text("Nöbetçi").font(.headline)
            Text("Sürüm \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Hiçbir veri cihazından çıkmaz.").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Nöbetçi'yi kaldır", role: .destructive) { confirmUninstall = true }
                .confirmationDialog("Nöbetçi kaldırılsın mı?", isPresented: $confirmUninstall) {
                    Button("Kaldır", role: .destructive) { model.uninstall() }
                    Button("Vazgeç", role: .cancel) {}
                } message: {
                    Text("Yüz profili, şifre ve tüm ayarlar silinir.")
                }
        }.padding()
    }

    private func sensitivityPicker(_ title: String, _ binding: Binding<Sensitivity>) -> some View {
        Picker(title, selection: binding) {
            Text("Düşük").tag(Sensitivity.low)
            Text("Orta").tag(Sensitivity.medium)
            Text("Yüksek").tag(Sensitivity.high)
        }
    }
}
