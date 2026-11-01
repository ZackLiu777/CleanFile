// 应用语言与格式化入口。
// 字符串从主 Bundle 的本地化资源读取；格式化区域随系统区域变化。
// 页面通过 AppL10n 获取字符串和区域，避免各处自行选择 Bundle 或缓存区域设置。
// 这里不维护应用内语言覆盖；语言和地区变化由系统设置决定。

import Foundation

/// 统一本地化查找与格式化区域的入口，便于页面使用应用资源和当前系统地区。
enum AppL10n {
    static var formattingLocale: Locale {
        .autoupdatingCurrent
    }

    /// 从主 Bundle 查找对应本地化字符串。
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .main)
    }
}
