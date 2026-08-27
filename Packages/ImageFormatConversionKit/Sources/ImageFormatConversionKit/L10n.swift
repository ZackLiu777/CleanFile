import Foundation

enum L10n {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    /// Runtime-composed keys must use Bundle lookup. Passing them through
    /// `String(localized:)` treats the interpolation itself as the resource key.
    static func dynamicString(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
