// 快捷压缩入口的预设说明。
// 根据媒体类型展示对应说明，提醒用户当前使用快捷压缩流程。
// 转换任务及输入输出仍由相应转换页面和状态对象负责。
// 图片和视频转换页面传入分类，组件据此选择本地化提示。
// 此视图不修改用户保留的专业转换参数，也不单独启动任务。

import SwiftUI

/// A preset shortcut shares the converter's import and output handling.
struct QuickCompressionSummary: View {
    let kind: ConversionUsageCategory
    @Environment(\.conversionTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("quick.ready"), systemImage: "checkmark.circle")
                .font(.headline)
            Text(L10n.string(kind == .video ? "quick.video.detail" : "quick.image.detail"))
                .font(.subheadline)
            Text(L10n.string("quick.originals"))
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversion.quickPreset")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.cardElevated, in: RoundedRectangle(cornerRadius: 18))
    }
}
