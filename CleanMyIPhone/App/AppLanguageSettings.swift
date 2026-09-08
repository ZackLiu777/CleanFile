import Foundation

enum AppL10n {
    static var formattingLocale: Locale {
        .autoupdatingCurrent
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .main)
    }
}
