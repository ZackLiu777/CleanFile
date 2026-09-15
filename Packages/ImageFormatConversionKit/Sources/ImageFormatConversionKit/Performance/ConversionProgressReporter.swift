//
//  ConversionProgressReporter.swift
//  ImageFormatConversionKit
//
//  Throttles high-frequency engine progress without moving codec work to MainActor.
//

import Foundation

/// Coalesces codec progress updates so long media files do not flood the UI actor.
actor ConversionProgressReporter {
    private let minimumStep: Double
    private let minimumInterval: Duration
    private let callback: @Sendable (Double) async -> Void
    private let clock = ContinuousClock()

    private var lastValue = -Double.infinity
    private var lastEmission: ContinuousClock.Instant?

    init(
        minimumStep: Double = 0.005,
        minimumInterval: Duration = .milliseconds(100),
        callback: @escaping @Sendable (Double) async -> Void
    ) {
        self.minimumStep = minimumStep
        self.minimumInterval = minimumInterval
        self.callback = callback
    }

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
