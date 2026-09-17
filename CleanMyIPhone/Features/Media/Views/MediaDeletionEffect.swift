//
//  MediaDeletionEffect.swift
//  CleanMyIPhone
//
//  PhotoKit 删除成功后的视觉反馈。缩略图快照与粒子只用于动画，
//  不参与也不提前模拟真实的媒体删除结果。
//

import QuartzCore
import Combine
import UIKit

@MainActor
protocol MediaDeletionEffectRendering: AnyObject {
    func captureDeletionEffect(for assetIDs: Set<String>) -> MediaDeletionEffectToken?
    func playDeletionEffect(_ token: MediaDeletionEffectToken, animated: Bool) async
    func discardDeletionEffect(_ token: MediaDeletionEffectToken)
}

struct MediaDeletionEffectToken: Hashable {
    fileprivate let id = UUID()
}

/// 在 SwiftUI 页面与 UIKit 网格之间传递删除动画请求，不介入 PhotoKit 删除逻辑。
@MainActor
final class MediaDeletionEffectController: ObservableObject {
    weak var renderer: (any MediaDeletionEffectRendering)?

    func capture(assetIDs: Set<String>) -> MediaDeletionEffectToken? {
        renderer?.captureDeletionEffect(for: assetIDs)
    }

    func play(_ token: MediaDeletionEffectToken?, animated: Bool) async {
        guard let token else { return }
        await renderer?.playDeletionEffect(token, animated: animated)
    }

    func discard(_ token: MediaDeletionEffectToken?) {
        guard let token else { return }
        renderer?.discardDeletionEffect(token)
    }
}

struct MediaDeletionSnapshot {
    let image: UIImage
    let frameInWindow: CGRect
}

/// 使用 Core Animation 的形状遮罩与粒子发射器实现照片撕裂消散。
@MainActor
enum MediaDeletionEffectAnimator {
    private static let duration: TimeInterval = 0.58
    private static let maximumStagger: TimeInterval = 0.12

    static func play(
        snapshots: [MediaDeletionSnapshot],
        in window: UIWindow,
        animated: Bool
    ) async {
        guard !snapshots.isEmpty else { return }

        let overlay = UIView(frame: window.bounds)
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = .clear
        window.addSubview(overlay)

        if !animated || UIAccessibility.isReduceMotionEnabled {
            snapshots.forEach { snapshot in
                let imageView = UIImageView(image: snapshot.image)
                imageView.frame = snapshot.frameInWindow
                imageView.contentMode = .scaleToFill
                overlay.addSubview(imageView)
            }
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    overlay.alpha = 0
                    overlay.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                }
            )
            try? await Task.sleep(for: .milliseconds(230))
            overlay.removeFromSuperview()
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        for (index, snapshot) in snapshots.enumerated() {
            let effectView = makeTornPhoto(snapshot: snapshot)
            overlay.addSubview(effectView.container)

            let progress = snapshots.count > 1
                ? Double(index) / Double(snapshots.count - 1)
                : 0
            let delay = progress * maximumStagger

            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.13) {
                effectView.emitter.birthRate = 0
            }

            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeIn)
            animator.addAnimations {
                effectView.topHalf.alpha = 0
                effectView.topHalf.transform = CGAffineTransform(
                    translationX: -effectView.container.bounds.width * 0.08,
                    y: -effectView.container.bounds.height * 0.28
                )
                .rotated(by: -0.07)
                .scaledBy(x: 0.96, y: 0.96)

                effectView.bottomHalf.alpha = 0
                effectView.bottomHalf.transform = CGAffineTransform(
                    translationX: effectView.container.bounds.width * 0.1,
                    y: effectView.container.bounds.height * 0.34
                )
                .rotated(by: 0.08)
                .scaledBy(x: 0.94, y: 0.94)

                effectView.tearLine.opacity = 0
                effectView.container.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            }
            animator.startAnimation(afterDelay: delay)
        }

        let totalDuration = duration + maximumStagger + 0.12
        try? await Task.sleep(for: .seconds(totalDuration))
        overlay.removeFromSuperview()
    }

    private static func makeTornPhoto(
        snapshot: MediaDeletionSnapshot
    ) -> (
        container: UIView,
        topHalf: UIImageView,
        bottomHalf: UIImageView,
        tearLine: CAShapeLayer,
        emitter: CAEmitterLayer
    ) {
        let container = UIView(frame: snapshot.frameInWindow)
        container.isUserInteractionEnabled = false
        container.clipsToBounds = false

        let bounds = container.bounds
        let tearPoints = makeTearPoints(in: bounds)
        let topPath = makeTopMask(in: bounds, tearPoints: tearPoints)
        let bottomPath = makeBottomMask(in: bounds, tearPoints: tearPoints)

        let topHalf = makeImageView(image: snapshot.image, bounds: bounds, maskPath: topPath)
        let bottomHalf = makeImageView(image: snapshot.image, bounds: bounds, maskPath: bottomPath)
        container.addSubview(topHalf)
        container.addSubview(bottomHalf)

        let tearPath = UIBezierPath()
        if let first = tearPoints.first {
            tearPath.move(to: first)
            tearPoints.dropFirst().forEach { tearPath.addLine(to: $0) }
        }
        let tearLine = CAShapeLayer()
        tearLine.path = tearPath.cgPath
        tearLine.fillColor = UIColor.clear.cgColor
        tearLine.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        tearLine.lineWidth = max(1, bounds.height * 0.012)
        tearLine.shadowColor = UIColor.black.cgColor
        tearLine.shadowOpacity = 0.22
        tearLine.shadowRadius = 2
        container.layer.addSublayer(tearLine)

        let emitter = makeEmitter(in: bounds, tearPoints: tearPoints)
        container.layer.addSublayer(emitter)

        return (container, topHalf, bottomHalf, tearLine, emitter)
    }

    private static func makeImageView(
        image: UIImage,
        bounds: CGRect,
        maskPath: UIBezierPath
    ) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.frame = bounds
        imageView.contentMode = .scaleToFill
        let mask = CAShapeLayer()
        mask.path = maskPath.cgPath
        imageView.layer.mask = mask
        return imageView
    }

    private static func makeTearPoints(in bounds: CGRect) -> [CGPoint] {
        let offsets: [CGFloat] = [-0.01, 0.045, -0.035, 0.025, -0.055, 0.04, -0.02, 0.03, -0.015]
        let baseY = bounds.height * 0.52
        return offsets.enumerated().map { index, offset in
            CGPoint(
                x: bounds.width * CGFloat(index) / CGFloat(offsets.count - 1),
                y: baseY + bounds.height * offset
            )
        }
    }

    private static func makeTopMask(
        in bounds: CGRect,
        tearPoints: [CGPoint]
    ) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: bounds.maxX, y: 0))
        tearPoints.reversed().forEach { path.addLine(to: $0) }
        path.close()
        return path
    }

    private static func makeBottomMask(
        in bounds: CGRect,
        tearPoints: [CGPoint]
    ) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = tearPoints.first else { return path }
        path.move(to: first)
        tearPoints.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: 0, y: bounds.maxY))
        path.close()
        return path
    }

    private static func makeEmitter(
        in bounds: CGRect,
        tearPoints: [CGPoint]
    ) -> CAEmitterLayer {
        let averageY = tearPoints.map(\.y).reduce(0, +) / CGFloat(max(tearPoints.count, 1))
        let emitter = CAEmitterLayer()
        emitter.frame = bounds
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: averageY)
        emitter.emitterSize = CGSize(width: bounds.width * 0.92, height: 1)
        emitter.renderMode = .oldestLast

        let fragment = CAEmitterCell()
        fragment.contents = particleImage()?.cgImage
        fragment.birthRate = 46
        fragment.lifetime = 0.55
        fragment.lifetimeRange = 0.18
        fragment.velocity = 58
        fragment.velocityRange = 36
        fragment.emissionLongitude = .pi / 2
        fragment.emissionRange = .pi * 0.82
        fragment.spin = 2.4
        fragment.spinRange = 4.8
        fragment.scale = 0.6
        fragment.scaleRange = 0.35
        fragment.scaleSpeed = -0.55
        fragment.alphaSpeed = -1.35
        fragment.color = UIColor.white.withAlphaComponent(0.9).cgColor
        emitter.emitterCells = [fragment]
        return emitter
    }

    private static func particleImage() -> UIImage? {
        let size = CGSize(width: 7, height: 5)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}
