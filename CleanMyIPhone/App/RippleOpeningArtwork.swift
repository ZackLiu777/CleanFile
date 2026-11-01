// 开屏标志与波纹画面的绘制。
// 画面根据传入时间计算进度，主题颜色由环境提供，不管理导航或启动任务。
// AppOpeningView 驱动画面时间与尺寸，标志路径按目标区域等比缩放。
// 静态帧与动态帧使用同一绘图逻辑；动画是否运行由调用方决定。

import SwiftUI

/// Production artwork is independent of the optional animation design gallery.
struct RippleOpeningArtwork: View {
    @Environment(\.appTheme) private var theme
    let time: Double
    let size: CGFloat

    private var progress: Double {
        let value = min(max(time / 1.65, 0), 1)
        return value * value * (3 - 2 * value)
    }

    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                let phase = min(max((time - Double(index) * 0.12) / 1.4, 0), 1)
                let eased = phase * phase * (3 - 2 * phase)
                let diameter = size * (0.84 - Double(index) * 0.10 - eased * 0.25)
                Circle()
                    .stroke(theme.accentPrimary.opacity(0.10 + Double(index) * 0.08),
                            lineWidth: index == 3 ? size * 0.014 : 1)
                    .frame(width: diameter, height: diameter)
                    .offset(y: (1 - eased) * size * Double(index - 2) * 0.035)
            }
            OpeningAppMark()
                .fill(theme.accentPrimary)
                .frame(width: size * 0.16, height: size * 0.16)
                .foregroundStyle(theme.accentPrimary)
                .scaleEffect(0.4 + progress * 0.6)
                .opacity(progress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Uses the app icon's two planes, cropped to their shared artwork bounds.
private struct OpeningAppMark: Shape {
    /// 将标志的两块原始轮廓等比缩放并居中到给定矩形。
    func path(in rect: CGRect) -> Path {
        let planes: [[CGPoint]] = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 512, y: 0),
             CGPoint(x: 512, y: 168), CGPoint(x: 168, y: 168),
             CGPoint(x: 168, y: 564), CGPoint(x: 0, y: 564)],
            [CGPoint(x: 224, y: 224), CGPoint(x: 564, y: 224),
             CGPoint(x: 564, y: 392), CGPoint(x: 392, y: 392),
             CGPoint(x: 392, y: 564), CGPoint(x: 224, y: 564)]
        ]
        let scale = min(rect.width, rect.height) / 564
        let origin = CGPoint(x: rect.midX - 282 * scale, y: rect.midY - 282 * scale)
        return Path { path in
            for plane in planes {
                path.addLines(plane.map {
                    CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale)
                })
                path.closeSubpath()
            }
        }
    }
}
