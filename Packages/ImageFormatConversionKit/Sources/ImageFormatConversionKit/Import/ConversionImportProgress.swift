//
//  文件职责：集中定义 ConversionImportProgress 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import Foundation
import Observation
import SwiftUI

/// 定义 `ConversionImportProgress` 的值语义数据与相关行为。
struct ConversionImportProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let currentFileName: String?
    let currentFileFraction: Double?

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

    /// 解析 `mapped` 对应的业务语义，并返回稳定的分类或映射结果。
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

/// Keeps the presentation phase of an import alive while a conversion detail
/// page is temporarily removed from the navigation stack.
@MainActor
@Observable
/// 封装 `ConversionImportSession` 的引用语义、状态与业务行为。
final class ConversionImportSession {
    var libraryProgress: ConversionImportProgress?
    var librarySessionID: UUID?
    var pendingCount = 0
    var previewURLs: [URL] = []
}

/// 定义 `AnimatedImportPercentage` 的值语义数据与相关行为。
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

/// 定义 `ConversionImportProgressView` 的值语义数据与相关行为。
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
                    .animation(.linear(duration: 0.12), value: progress.fractionCompleted)
            }

            ProgressView(value: progress.fractionCompleted)
                .tint(theme.accent)
                .animation(.linear(duration: 0.12), value: progress.fractionCompleted)
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

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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
