//
//  定义转换导入进度、跨页面保留的会话状态和进度展示视图。
//  单文件进度与已完成数量合成为总进度，并支持映射到多阶段区间。
//  调试构建额外提供确定性界面宿主，用于验证进度呈现。
//  各转换页面通过会话对象保留导入展示状态，视图将数值呈现为进度和文件名。
//  进度对象只描述当前工作，不拥有导入任务，也不负责取消或清理文件。
//

import Foundation
import Observation
import SwiftUI

/// 表示批量导入已完成项数、总数和当前文件的可选进度。
struct ConversionImportProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let currentFileName: String?
    let currentFileFraction: Double?

    /// 记录已完成项目数、总数、当前文件名及可选的文件内进度。
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

    /// 将当前文件进度加入已完成项，并将结果限制在零到一之间。
    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        let current = min(max(currentFileFraction ?? 0, 0), 1)
        return min(max((Double(completed) + current) / Double(total), 0), 1)
    }

    /// 向下取整为展示用百分比，避免未完成时提前显示 100%。
    var percentage: Int {
        Int((fractionCompleted * 100).rounded(.down))
    }

    /// 将整体进度映射到阶段区间，供多阶段导入合并展示。
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
/// 在详情页临时离开导航栈时保留图库导入的展示状态。
final class ConversionImportSession {
    var libraryProgress: ConversionImportProgress?
    var librarySessionID: UUID?
    var pendingCount = 0
    var previewURLs: [URL] = []
}

/// 插值展示百分比，同时使用等宽数字和无障碍标识。
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

/// 展示总进度和当前文件名，并为辅助功能提供百分比值。
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

            WaveProgressView(
                progress: progress.fractionCompleted,
                tint: theme.accent
            )
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

    /// 创建导入进度的界面自动化展示入口。
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
