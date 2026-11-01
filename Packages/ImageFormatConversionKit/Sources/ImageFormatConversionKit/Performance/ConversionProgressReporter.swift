//
//  合并编解码器高频进度，减少展示层收到的更新次数。
//  Actor 保存最近一次值和时间，按最小增量或时间间隔决定是否回调。
//  值限制在零到一之间，并拒绝倒退；起点、终点和强制更新可绕过节流。
//  音频转换引擎将提取和编码进度交给报告器，再转发给展示层。
//  此对象管理报告频率和数值，不拥有底层编码任务或决定任务成败。
//

//
//  ConversionProgressReporter.swift
//  ImageFormatConversionKit
//
//  Throttles high-frequency engine progress without moving codec work to MainActor.
//

import Foundation

/// 串行维护进度快照，合并过于频繁的编解码进度回调。
actor ConversionProgressReporter {
    private let minimumStep: Double
    private let minimumInterval: Duration
    private let callback: @Sendable (Double) async -> Void
    private let clock = ContinuousClock()

    private var lastValue = -Double.infinity
    private var lastEmission: ContinuousClock.Instant?

    /// 设置最小进度增量、最长静默间隔和异步回调。
    init(
        minimumStep: Double = 0.005,
        minimumInterval: Duration = .milliseconds(100),
        callback: @escaping @Sendable (Double) async -> Void
    ) {
        self.minimumStep = minimumStep
        self.minimumInterval = minimumInterval
        self.callback = callback
    }

    /// 进度达到增量或时间阈值时回调；拒绝小于上次值的更新。
    /// 起点、终点和强制报告跳过节流，但仍遵守不倒退约束。
    func report(_ value: Double, force: Bool = false) async {
        let clampedValue = min(max(value, 0), 1)
        let now = clock.now
        let enoughProgress = clampedValue - lastValue >= minimumStep
        let enoughTime = lastEmission.map { $0.duration(to: now) >= minimumInterval } ?? true

        guard force || clampedValue == 0 || clampedValue == 1 || enoughProgress || enoughTime else {
            return
        }
        guard clampedValue >= lastValue else { return }

        lastValue = clampedValue
        lastEmission = now
        await callback(clampedValue)
    }
}
