import Foundation
import SwiftUI

struct ConversionImportProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let currentFileName: String?
    let currentFileFraction: Double?

    init(
        completed: Int,
        total: Int,
        currentFileName: String?,
        currentFileFraction: Double? = nil
    ) {
        self.completed = completed
        self.total = total
        self.currentFileName = currentFileName
        self.currentFileFraction = currentFileFraction
    }

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        let current = min(max(currentFileFraction ?? 0, 0), 1)
        return min(max((Double(completed) + current) / Double(total), 0), 1)
    }

    var percentage: Int {
        Int((fractionCompleted * 100).rounded(.down))
    }

    func mapped(to range: ClosedRange<Double>) -> ConversionImportProgress {
        let lower = min(max(range.lowerBound, 0), 1)
        let upper = min(max(range.upperBound, lower), 1)
        return ConversionImportProgress(
            completed: 0,
            total: 1,
            currentFileName: currentFileName,
            currentFileFraction: lower + ((upper - lower) * fractionCompleted)
        )
    }
}

private struct AnimatedImportPercentage: View, Animatable {
    var value: Double

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int((min(max(value, 0), 1) * 100).rounded(.down)))%")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("conversion.import.percentage")
    }
}

struct ConversionImportProgressView: View {
    @Environment(\.conversionTheme) private var theme
    let progress: ConversionImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("import.progress.title"))
                    .font(.headline)
                Spacer()
                AnimatedImportPercentage(value: progress.fractionCompleted)
                    .animation(.linear(duration: 0.18), value: progress.fractionCompleted)
            }

            ProgressView(value: progress.fractionCompleted)
                .tint(theme.accent)
                .animation(.linear(duration: 0.18), value: progress.fractionCompleted)
                .accessibilityValue(Text("\(progress.percentage)%"))
                .accessibilityIdentifier("conversion.import.progressBar")

            if let fileName = progress.currentFileName, !fileName.isEmpty {
                Text(fileName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .converterCard()
    }
}

#if DEBUG
/// A deterministic host for verifying the production import-progress view in UI tests.
/// It is compiled only in debug builds and is never reachable from the normal app flow.
public struct ConversionImportProgressUITestHarness: View {
    @State private var progress = ConversionImportProgress(
        completed: 0,
        total: 1,
        currentFileName: "LargeVideo.mov",
        currentFileFraction: 0
    )

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            ConversionImportProgressView(progress: progress)

            HStack {
                Button("Simulate 50%") {
                    progress = ConversionImportProgress(
                        completed: 0,
                        total: 1,
                        currentFileName: "LargeVideo.mov",
                        currentFileFraction: 0.5
                    )
                }
                .accessibilityIdentifier("conversion.import.simulateHalf")

                Button("Simulate 100%") {
                    progress = ConversionImportProgress(
                        completed: 1,
                        total: 1,
                        currentFileName: "LargeVideo.mov",
                        currentFileFraction: 0
                    )
                }
                .accessibilityIdentifier("conversion.import.simulateComplete")
            }
        }
        .padding(24)
        .environment(\.conversionTheme, .system)
    }
}
#endif
