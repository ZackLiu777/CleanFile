// 分段式质量滑块的布局、手势与动态效果。
// 绑定值由父视图持有；手势将位置映射到滑块范围，并提供分段吸附反馈。
// 显示颜色来自转换主题，具体数值含义由调用方定义。
// 手势与无障碍调整操作共享数值范围和步长，父视图接收选择结果。
// 开启减少动态效果时暂停流光展示；滑块本身不触发编码。

//
//  SegmentedStreamSlider.swift
//  ImageFormatConversionKit
//


import SwiftUI

/// A magnetic, segmented quality control whose colors follow the conversion theme.
struct SegmentedStreamSlider: View {
    @Binding var value: Double

    private let range: ClosedRange<Double>
    private let step: Double
    private let totalSegments: Int
    private let title: String
    private let pausesAnimation: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.conversionTheme) private var theme

    /// 设置绑定值、范围、步长及分段数量；至少保留两个显示分段。
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0.1 ... 1,
        step: Double = 0.1,
        totalSegments: Int = 10,
        title: String = L10n.string("settings.quality"),
        pausesAnimation: Bool = false
    ) {
        _value = value
        self.range = range
        self.step = step
        self.totalSegments = max(totalSegments, 2)
        self.title = title
        self.pausesAnimation = pausesAnimation
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .appTypeface(.body, size: 15, relativeTo: .body, weight: .medium)
                    .foregroundStyle(theme.textPrimary.opacity(0.85))

                Spacer()

                Text(value, format: .percent.precision(.fractionLength(0)))
                    .appTypeface(.body, size: 15, relativeTo: .body, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            }

            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || pausesAnimation)) { timeline in
                    let streamOffset = (reduceMotion || pausesAnimation) ? 0 : streamOffset(at: timeline.date)

                    HStack(spacing: 4) {
                        ForEach(0 ..< totalSegments, id: \.self) { index in
                            segment(index: index, streamOffset: streamOffset)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(width: geometry.size.width))
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 36)

            HStack {
                Text(L10n.string("quality.smaller"))
                Spacer()
                Text(L10n.string("quality.balanced"))
                Spacer()
                Text(L10n.string("quality.best"))
            }
            .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                setValue(value + step)
            case .decrement:
                setValue(value - step)
            @unknown default:
                break
            }
        }
        .sensoryFeedback(.selection, trigger: activeSegment)
    }

    private var activeSegment: Int {
        let percentage = min(max(value, 0), 1)
        return min(Int((percentage * Double(totalSegments)).rounded()), totalSegments)
    }

    /// 绘制一个分段，并根据激活状态和减少动态效果设置调整视觉反馈。
    private func segment(index: Int, streamOffset: CGFloat) -> some View {
        let isActive = index < activeSegment

        return GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [theme.accent.opacity(0.68), theme.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(theme.textSecondary.opacity(0.10))
                    )

                if isActive, !reduceMotion, !pausesAnimation {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.42), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: streamOffset * geometry.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .frame(height: 14)
        .scaleEffect(y: isActive ? 1.15 : 0.95)
        .shadow(color: isActive ? theme.accent.opacity(0.30) : .clear, radius: 3, y: 1.5)
        .animation(.spring(response: 0.25, dampingFraction: 0.72), value: isActive)
    }

    /// 将时间映射为循环流光偏移，不改变实际滑块值。
    private func streamOffset(at date: Date) -> CGFloat {
        let duration = 1.8
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return -0.35 + CGFloat(elapsed / duration) * 1.6
    }

    /// 将拖动位置映射到滑块值，使选择随手势连续更新。
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard width > 0 else { return }
                let normalized = min(max(gesture.location.x / width, 0), 1)
                let rawValue = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
                setValue(rawValue)
            }
    }

    /// 限制并更新绑定值，使用分段间隔吸附到可选位置。
    private func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        let stepped = ((clamped - range.lowerBound) / step).rounded() * step + range.lowerBound
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}

/// 供产品介绍复用的只读码率控件；不会更改实际转换设置。
public struct ConversionBitrateDemonstration: View {
    private let value: Double
    private let theme: ConversionTheme
    private let pausesAnimation: Bool

    public init(value: Double, theme: ConversionTheme, pausesAnimation: Bool = false) {
        self.value = value
        self.theme = theme
        self.pausesAnimation = pausesAnimation
    }

    public var body: some View {
        SegmentedStreamSlider(
            value: .constant(value),
            title: L10n.string("video.settings.bitrate"),
            pausesAnimation: pausesAnimation
        )
        .environment(\.conversionTheme, theme)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
