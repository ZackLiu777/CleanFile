#if os(iOS)
import SwiftUI
import UIKit

struct ConversionReplacementCardSnapshot {
    let image: UIImage
    let frameInWindow: CGRect
}

@MainActor
enum ConversionReplacementCardDeletionEffect {
    static func capture(frame: CGRect, in window: UIWindow) -> ConversionReplacementCardSnapshot? {
        let clippedFrame = frame.intersection(window.bounds)
        guard clippedFrame.width > 1, clippedFrame.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window.screen.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: clippedFrame.size, format: format).image { context in
            context.cgContext.translateBy(x: -clippedFrame.minX, y: -clippedFrame.minY)
            window.layer.render(in: context.cgContext)
        }
        return ConversionReplacementCardSnapshot(image: image, frameInWindow: clippedFrame)
    }

    static func play(
        snapshot: ConversionReplacementCardSnapshot,
        in window: UIWindow,
        animated: Bool,
        hideOriginal: () -> Void
    ) async {
        let overlay = UIView(frame: window.bounds)
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        window.addSubview(overlay)
        let fragments = makeFragments(snapshot: snapshot, in: overlay)
        hideOriginal()
        await Task.yield()

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: 0.16) {
                fragments.forEach { $0.alpha = 0 }
            }
            try? await Task.sleep(for: .milliseconds(190))
            overlay.removeFromSuperview()
            return
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        for (index, fragment) in fragments.enumerated() {
            let row = index / 10
            let column = index % 10
            let horizontal = CGFloat(column) - 4.5
            let delay = Double(row + column) * 0.008
            UIView.animate(
                withDuration: 0.42,
                delay: delay,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                fragment.alpha = 0
                fragment.transform = CGAffineTransform(
                    translationX: horizontal * 4.8,
                    y: 18 + CGFloat(row) * 2
                )
                .rotated(by: CGFloat((index % 7) - 3) * 0.12)
                .scaledBy(x: 0.18, y: 0.18)
            }
        }
        try? await Task.sleep(for: .milliseconds(570))
        overlay.removeFromSuperview()
    }

    private static func makeFragments(
        snapshot: ConversionReplacementCardSnapshot,
        in overlay: UIView
    ) -> [UIImageView] {
        let columns = 10
        let rows = max(3, min(6, Int((10 * snapshot.frameInWindow.height / max(snapshot.frameInWindow.width, 1)).rounded())))
        let width = snapshot.frameInWindow.width / CGFloat(columns)
        let height = snapshot.frameInWindow.height / CGFloat(rows)
        return (0..<(rows * columns)).map { index in
            let row = index / columns
            let column = index % columns
            let fragment = UIImageView(image: snapshot.image)
            fragment.contentMode = .scaleToFill
            fragment.clipsToBounds = true
            fragment.frame = CGRect(
                x: snapshot.frameInWindow.minX + CGFloat(column) * width,
                y: snapshot.frameInWindow.minY + CGFloat(row) * height,
                width: width + 0.5,
                height: height + 0.5
            )
            fragment.layer.contentsRect = CGRect(
                x: CGFloat(column) / CGFloat(columns),
                y: CGFloat(row) / CGFloat(rows),
                width: 1 / CGFloat(columns),
                height: 1 / CGFloat(rows)
            )
            overlay.addSubview(fragment)
            return fragment
        }
    }
}
#endif

struct ConversionReplacementFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct ConversionReplacementCategoryFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
