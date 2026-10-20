import SwiftUI

/// İlk kurulum sihirbazı (spec §8.2): tanıtım → izinler → şifre → yüz kaydı → bitti.
/// Canlı yüz yakalama cihazda çalışır; burada akış ve depolama kurulur.
struct SetupView: View {
    let model: AppModel
    var onFinish: () -> Void

    @State private var step = 0
    @State private var passcode = ""
    @State private var passcodeConfirm = ""
    @State private var captured = 0
    @State private var target = 50
    @State private var profile: [[Float]] = []
    @State private var enrolling = false

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case 0: intro
            case 1: permissions
            case 2: passcodeStep
            case 3: enrollStep
            default: done
            }
        }
        .padding(28)
        .frame(width: 480, height: 420)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.system(size: 56))
            Text(L10n.t("setup.title")).font(.title.weight(.semibold))
            Text(L10n.t("setup.intro.body")).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button(L10n.t("setup.next")) { step = 1 }.controlSize(.large).buttonStyle(.borderedProminent)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("setup.permissions")).font(.title2.weight(.semibold))
            Label("Kamera — sen yokken kimin geçtiğini anlamak için", systemImage: "camera")
            Label("Erişilebilirlik — kilitliyken girdiyi engellemek için", systemImage: "hand.raised")
            Label("Bildirimler — nöbet özeti için", systemImage: "bell")
            Spacer()
            Button(L10n.t("setup.next")) { step = 2 }.controlSize(.large).buttonStyle(.borderedProminent)
        }
    }

    private var passcodeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("setup.passcode")).font(.title2.weight(.semibold))
            Text("En az 6 karakter. Yüz tanınmazsa bununla açarsın.").foregroundStyle(.secondary)
            SecureField("Şifre", text: $passcode)
            SecureField("Şifre (tekrar)", text: $passcodeConfirm)
            Spacer()
            Button(L10n.t("setup.next")) { step = 3 }
                .controlSize(.large).buttonStyle(.borderedProminent)
                .disabled(passcode.count < 6 || passcode != passcodeConfirm)
        }
    }

    private var enrollStep: some View {
        VStack(spacing: 16) {
            Text(L10n.t("setup.enroll")).font(.title2.weight(.semibold))
            Text("Başını yavaşça çevirerek yüzünü kaydet.").foregroundStyle(.secondary)
            ProgressView(value: Double(captured), total: Double(target))
                .frame(maxWidth: 300)
            Text("\(captured) / \(target)").monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if !enrolling {
                Button("Yüz kaydını başlat") { startEnrollment() }
                    .controlSize(.large).buttonStyle(.borderedProminent)
            } else if captured >= target {
                Button(L10n.t("setup.next")) { step = 4 }.controlSize(.large).buttonStyle(.borderedProminent)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text(L10n.t("setup.done")).font(.title.weight(.semibold))
            Text("Artık menü çubuğundan 'Uzaktayım' diyebilirsin.").foregroundStyle(.secondary)
            Spacer()
            Button(L10n.t("setup.finish")) { finish() }.controlSize(.large).buttonStyle(.borderedProminent)
        }
    }

    private func startEnrollment() {
        enrolling = true
        captured = 0
        model.runEnrollment(onProgress: { count, total in
            Task { @MainActor in captured = count; target = total }
        }, onComplete: { vectors in
            Task { @MainActor in profile = vectors; model.stopEnrollment() }
        })
    }

    private func finish() {
        try? model.enroll(profile: profile, passcode: passcode)
        onFinish()
    }
}
