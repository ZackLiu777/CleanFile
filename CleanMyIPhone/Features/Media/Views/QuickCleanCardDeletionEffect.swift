//
//  QuickCleanCardDeletionEffect.swift
//  CleanMyIPhone
//
//  快速清理分类卡片的顺序碎片化反馈。动画仅在 PhotoKit 删除成功后播放。
//

import SwiftUI
import UIKit

struct QuickCleanCardSnapshot {
    let image: UIImage
    let frameInWindow: CGRect
}

@MainActor
enum QuickCleanCardDeletionEffect {
    /// 从当前窗口截取单张分类卡片。每轮动画前重新截取，以匹配上一张移除后的新位置。
    static func capture(frame: CGRect, in window: UIWindow) -> QuickCleanCardSnapshot? {
        let clippedFrame = frame.intersection(window.bounds)
        guard clippedFrame.width > 1, clippedFrame.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window.screen.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: clippedFrame.size,
            format: format
        ).image { context in
            context.cgContext.translateBy(x: -clippedFrame.minX, y: -clippedFrame.minY)
            window.layer.render(in: context.cgContext)
        }
        return QuickCleanCardSnapshot(image: image, frameInWindow: clippedFrame)
    }

    /// 将卡片图像切成小块并消散。安装碎片图层后再隐藏原卡片，避免出现空白帧。
    static func play(
        snapshot: QuickCleanCardSnapshot,
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
                fragments.forEach {
                    $0.alpha = 0
                    $0.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
                }
            }
            try? await Task.sleep(for: .milliseconds(190))
            overlay.removeFromSuperview()
            return
        }

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let rows = max(1, Int(ceil(Double(fragments.count) / 10.0)))
        for (index, fragment) in fragments.enumerated() {
            let row = index / 10
            let column = index % 10
            let horizontal = CGFloat(column) - 4.5
            let vertical = CGFloat(row) - CGFloat(rows - 1) / 2
            let delay = Double(row + column) * 0.008
            let rotation = (CGFloat((index % 7) - 3) * 0.12)

            UIView.animate(
                withDuration: 0.42,
                delay: delay,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                fragment.alpha = 0
                fragment.transform = CGAffineTransform(
                    translationX: horizontal * 4.8,
                    y: 18 + abs(vertical) * 5.5
                )
                .rotated(by: rotation)
                .scaledBy(x: 0.18, y: 0.18)
            }
        }

        try? await Task.sleep(for: .milliseconds(570))
        overlay.removeFromSuperview()
    }

    private static func makeFragments(
        snapshot: QuickCleanCardSnapshot,
        in overlay: UIView
    ) -> [UIImageView] {
        let columns = 10
        let aspectRatio = snapshot.frameInWindow.height / max(snapshot.frameInWindow.width, 1)
        let rows = max(3, min(6, Int((CGFloat(columns) * aspectRatio).rounded())))
        let fragmentWidth = snapshot.frameInWindow.width / CGFloat(columns)
        let fragmentHeight = snapshot.frameInWindow.height / CGFloat(rows)

        return (0..<(rows * columns)).map { index in
            let row = index / columns
            let column = index % columns
            let fragment = UIImageView(image: snapshot.image)
            fragment.contentMode = .scaleToFill
            fragment.clipsToBounds = true
            fragment.frame = CGRect(
                x: snapshot.frameInWindow.minX + CGFloat(column) * fragmentWidth,
                y: snapshot.frameInWindow.minY + CGFloat(row) * fragmentHeight,
                width: fragmentWidth + 0.5,
                height: fragmentHeight + 0.5
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

struct QuickCleanCategoryFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MediaQuickCleanViewModel.Category.ID: CGRect] = [:]

    static func reduce(
        value: inout [MediaQuickCleanViewModel.Category.ID: CGRect],
        nextValue: () -> [MediaQuickCleanViewModel.Category.ID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
