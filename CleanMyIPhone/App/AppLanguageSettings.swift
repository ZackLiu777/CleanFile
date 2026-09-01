import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: AppL10n.string("Follow System")
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    static let defaultsKey = "appLanguageOverride"

    @Published private(set) var language: AppLanguage

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        language = userDefaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func select(_ language: AppLanguage) {
        guard self.language != language else { return }

        // Persist first so programmatic localization observes the new bundle
        // during the same SwiftUI update that publishes the language change.
        if language == .system {
            userDefaults.removeObject(forKey: Self.defaultsKey)
        } else {
            userDefaults.set(language.rawValue, forKey: Self.defaultsKey)
        }
        self.language = language
    }
}

enum AppL10n {
    static var formattingLocale: Locale {
        selectedLanguage?.locale ?? .autoupdatingCurrent
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: localizedBundle)
    }

    private static var selectedLanguage: AppLanguage? {
        UserDefaults.standard.string(forKey: AppLanguageSettings.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:))
    }

    private static var localizedBundle: Bundle {
        guard let language = selectedLanguage,
              language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
