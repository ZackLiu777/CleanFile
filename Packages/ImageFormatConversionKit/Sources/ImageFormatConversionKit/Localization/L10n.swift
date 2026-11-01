//
//  集中读取转换包中的本地化资源，并提供带参数的格式化入口。
//  静态资源键使用包资源查找，运行时拼接的键通过 Bundle 查询。
//  格式化使用当前自动更新的区域设置，以适应系统语言和数字格式。
//  转换页面和模型通过统一入口获取资源包内的界面文本与格式化文案。
//  此处只处理字符串查找，不负责更改宿主应用的语言设置。
//

import Foundation

/// 在 Swift Package 资源包内解析本地化文本。
enum L10n {
    private static var formattingLocale: Locale {
        .autoupdatingCurrent
    }

    /// 查找编译时声明的本地化资源键。
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    /// 通过 Bundle 查找运行时组合的键，避免插值表达式被当作资源键。
    static func dynamicString(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 按当前区域设置格式化本地化模板和参数。
    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: formattingLocale, arguments: arguments)
    }
}
