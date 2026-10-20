import SwiftUI
import NobetciCore

@main
struct NobetciApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
                .onAppear { model.presentSetupIfNeeded() }
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }

    private var menuIcon: String {
        switch model.state {
        case .off: "shield"
        case .preparing: "shield.lefthalf.filled"
        case .guarding: "shield.fill"
        case .locked: "lock.shield.fill"
        }
    }
}
