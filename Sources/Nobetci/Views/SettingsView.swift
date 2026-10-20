import SwiftUI
import NobetciCore

/// Ayarlar penceresi (spec §8.5). Korumayı zayıflatan değişiklikler uygulama
/// açıkken kaydedilir; şifre onayı ve hassas işlemler cihazda eklenecek.
struct SettingsView: View {
    let model: AppModel
    @State private var settings: GuardSettings
    @State private var confirmUninstall = false

    init(model: AppModel) {
        self.model = model
        _settings = State(initialValue: model.currentSettings())
    }

    var body: some View {
        TabView {
            general.tabItem { Label(L10n.t("settings.general"), systemImage: "gear") }
            detection.tabItem { Label(L10n.t("settings.detection"), systemImage: "sensor") }
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

    private var unlock: some View {
        Form {
            Toggle("Sıkı mod (baş hareketi iste)", isOn: $settings.strictMode)
            Text("Yüz profilini yenileme ve şifre değiştirme cihazda eklenecek (kimlik doğrulamalı).")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding()
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
