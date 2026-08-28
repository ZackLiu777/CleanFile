//
//  文件职责：集中定义 L10n 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import Foundation

/// 定义 `L10n` 使用的有限状态或选项集合。
enum L10n {
    /// 生成 `string` 使用的展示文本，保持格式与本地化规则一致。
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }

    /// Runtime-composed keys must use Bundle lookup. Passing them through
    /// `String(localized:)` treats the interpolation itself as the resource key.
    static func dynamicString(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 生成 `format` 使用的展示文本，保持格式与本地化规则一致。
    static func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
