import Foundation

/// Türkçe metin erişimi. Tüm kullanıcıya görünen metinler `tr.lproj/Localizable.strings`
/// tek kaynağında; ileride İngilizce eklemek için yalnızca yeni bir .lproj gerekir.
enum L10n {
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
        if args.isEmpty { return format }
        return String(format: format, locale: Locale(identifier: "tr_TR"), arguments: args)
    }
}
