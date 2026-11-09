import Foundation

/// Türkçe metin erişimi. Tüm kullanıcıya görünen metinler `tr.lproj/Localizable.strings`
/// tek kaynağında; ileride İngilizce eklemek için yalnızca yeni bir .lproj gerekir.
enum L10n {
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        if args.isEmpty { return format }
        return String(format: format, locale: Locale(identifier: "tr_TR"), arguments: args)
    }

    /// The SwiftPM resource bundle (`Nobetci_Nobetci.bundle`).
    ///
    /// Do not use `Bundle.module` here. For an executable target, the SwiftPM accessor
    /// examines only the root of the `.app` and an absolute `.build` path on the build Mac.
    /// If the bundle is not in these locations, the accessor calls `fatalError`.
    /// `scripts/bundle.sh` puts the bundle in `Contents/Resources`. A bundle in the root
    /// of the `.app` causes a code signature error. For this reason, the application
    /// stopped at the first `L10n.t` call on all Macs except the build Mac.
    static let bundle: Bundle = {
        let name = "Nobetci_Nobetci.bundle"
        let directories = [
            Bundle.main.resourceURL,                                  // Nöbetçi.app/Contents/Resources
            Bundle.main.executableURL?.deletingLastPathComponent(),   // .build/<configuration>/ (swift run)
        ]
        for case let directory? in directories {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)) { return bundle }
        }
        // If L10n cannot find the bundle, it shows the text keys. The application does not stop.
        return Bundle.main
    }()
}
