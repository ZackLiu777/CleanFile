// 转换页面共用的操作按钮。
// 调用方提供标题、图标、颜色和动作，使不同转换入口复用一致的交互外观。
// 该组件只转发用户操作，不决定转换权限或执行文件处理。
// 专业转换和媒体快捷压缩入口可提供各自文案、颜色和点击回调。
// 按压外观复用转换页面的按钮样式，操作的可用性由调用方控制。

import SwiftUI

/// The shared action button used by professional conversion and media quick compression.
@MainActor
public struct ConversionActionButton: View {
    private let title: String
    private let systemImage: String
    private let accentColor: Color
    private let foregroundColor: Color
    private let action: () -> Void

    /// 设置按钮标题、图标、外观和点击回调，由调用方决定操作内容。
    public init(
        title: String,
        systemImage: String = "arrow.triangle.2.circlepath",
        accentColor: Color,
        foregroundColor: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.foregroundColor = foregroundColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                Text(title.uppercased())
                    .appTypeface(.subheadline.weight(.black), size: 14, relativeTo: .subheadline, weight: .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .buttonStyle(ConversionPhysicalActionButtonStyle(faceColor: accentColor, edgeColor: foregroundColor))
    }
}
