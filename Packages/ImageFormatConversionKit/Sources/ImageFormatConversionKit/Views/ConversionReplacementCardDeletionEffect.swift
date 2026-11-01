// 原件替换审阅页的卡片消失效果。
// 捕获窗口中卡片的视觉快照并播放碎片效果；坐标由页面偏好值提供。
// 效果仅呈现已完成操作的反馈，不负责执行照片删除或文件替换。
// 审阅页面提供卡片位置和截图，效果完成后移除临时覆盖视图。
// 减少动态效果时使用简化淡出；动画结果不改变文件操作结果。

#if os(iOS)
import SwiftUI
import UIKit

/// 保存卡片截图与窗口坐标，供后续视觉反馈使用。
struct ConversionReplacementCardSnapshot {
    let image: UIImage
    let frameInWindow: CGRect
}

/// 负责捕获和播放审阅卡片的视觉效果，不执行实际文件或照片删除。
@MainActor
enum ConversionReplacementCardDeletionEffect {
    /// 截取指定窗口区域；无法取得有效画面时返回空值。
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

    /// 按动态效果设置播放或简化反馈，并通过回调隐藏原始卡片。
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

    /// 将快照划分为网格并放入覆盖层，供后续动画独立移动和淡出。
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

/// 收集各候选卡片在窗口中的位置。
struct ConversionReplacementFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    /// 合并子视图上报的位置；同一键出现多次时使用最新值。
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// 收集分类卡片在窗口中的位置。
struct ConversionReplacementCategoryFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    /// 合并子视图上报的位置；同一键出现多次时使用最新值。
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
