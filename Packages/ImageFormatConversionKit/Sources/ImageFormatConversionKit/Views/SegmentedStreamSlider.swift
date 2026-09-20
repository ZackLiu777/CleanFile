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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.conversionTheme) private var theme

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0.1 ... 1,
        step: Double = 0.1,
        totalSegments: Int = 10
    ) {
        _value = value
        self.range = range
        self.step = step
        self.totalSegments = max(totalSegments, 2)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.string("settings.quality"))
                    .appTypeface(.body, size: 15, relativeTo: .body, weight: .medium)
                    .foregroundStyle(theme.textPrimary.opacity(0.85))

                Spacer()

                Text(value, format: .percent.precision(.fractionLength(0)))
                    .appTypeface(.body, size: 15, relativeTo: .body, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
            }

            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let streamOffset = reduceMotion ? 0 : streamOffset(at: timeline.date)

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
        .accessibilityLabel(L10n.string("settings.quality"))
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

                if isActive, !reduceMotion {
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

    private func streamOffset(at date: Date) -> CGFloat {
        let duration = 1.8
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return -0.35 + CGFloat(elapsed / duration) * 1.6
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard width > 0 else { return }
                let normalized = min(max(gesture.location.x / width, 0), 1)
                let rawValue = range.lowerBound + Double(normalized) * (range.upperBound - range.lowerBound)
                setValue(rawValue)
            }
    }

    private func setValue(_ newValue: Double) {
        let clamped = min(max(newValue, range.lowerBound), range.upperBound)
        let stepped = ((clamped - range.lowerBound) / step).rounded() * step + range.lowerBound
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}
