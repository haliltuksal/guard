import SwiftUI
import NobetciCore

/// Kalkanın cam kartı: kilit simgesi, sahip adı, "Kamera etkin", saat ve duruma
/// göre değişen mesaj; bir tuşa basılınca beliren şifre noktaları.
struct ShieldView: View {
    let model: AppModel
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(L10n.t("shield.title", NSFullUserName()))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Label(L10n.t("shield.camera"), systemImage: "video.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Text(now, format: .dateTime.hour().minute().weekday(.wide))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                if model.passcodeCount > 0 {
                    HStack(spacing: 10) {
                        ForEach(0..<model.passcodeCount, id: \.self) { _ in
                            Circle().fill(.white).frame(width: 10, height: 10)
                        }
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { now = $0 }
    }

    private var message: String {
        switch model.shieldMessage {
        case .searching: L10n.t("shield.searching")
        case .blink: L10n.t("shield.blink", NSFullUserName().split(separator: " ").first.map(String.init) ?? "")
        case .bystander: L10n.t("shield.bystander")
        case .retry(let s): L10n.t("shield.retry", s)
        case .gesture(let turn):
            switch turn {
            case .left: L10n.t("shield.turn.left")
            case .right: L10n.t("shield.turn.right")
            case .up: L10n.t("shield.turn.up")
            }
        }
    }
}
