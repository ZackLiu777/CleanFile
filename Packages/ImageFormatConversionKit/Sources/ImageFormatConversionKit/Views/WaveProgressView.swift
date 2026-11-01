// 转换相关流程共用的波浪进度指示器。
// 按传入进度绘制填充比例，并根据减少动态效果设置调整动画。
// 组件仅展示进度，不决定任务是否完成或成功。
// 导入及转换界面传入数值、颜色和高度，组件将进度限制在可显示范围。
// 减少动态效果时不启动循环波浪；组件不拥有或取消后台任务。

import SwiftUI

/// A compact animated progress indicator shared by media analysis, import,
/// and conversion surfaces.
public struct WaveProgressView: View {
    private let progress: Double
    private let height: CGFloat
    private let tint: Color
    @State private var waveOffset: Angle = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 设置显示高度和颜色，并将输入进度限制在零到一之间。
    public init(progress: Double, height: CGFloat = 12, tint: Color = .accentColor) {
        self.progress = min(max(progress, 0), 1)
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.06))

                WaveProgressShape(
                    offset: waveOffset,
                    waveHeight: min(2, height * 0.2)
                )
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.72),
                            tint
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geometry.size.width * progress)
                .clipShape(Capsule())
                .shadow(
                    color: tint.opacity(0.3),
                    radius: 3,
                    y: 1
                )
                .animation(.easeOut(duration: 0.18), value: progress)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                waveOffset = .degrees(360)
            }
        }
    }
}

/// 根据进度和波形偏移生成指示器填充路径。
private struct WaveProgressShape: Shape {
    var offset: Angle
    let waveHeight: CGFloat

    var animatableData: Double {
        get { offset.degrees }
        set { offset = .degrees(newValue) }
    }

    /// 根据偏移和波高绘制闭合填充路径；尺寸无效时返回空路径。
    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))

        for x in stride(from: CGFloat.zero, through: rect.width, by: 2) {
            let phase = x / rect.width * .pi * 4 + offset.radians
            let y = rect.height / 2 + sin(phase) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}
