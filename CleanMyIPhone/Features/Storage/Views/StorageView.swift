//
//  StorageView.swift
//  CleanMyIPhone
//

//
//  文件职责：声明 Storage 界面结构、交互入口与展示状态。
//  所属模块：CleanMyIPhone。
//

import SwiftUI
import UniformTypeIdentifiers

/// 定义 `StorageView` 的值语义数据与相关行为。
struct StorageView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var viewModel: FileScannerViewModel
    let isTabActive: Bool
    @State private var isImporterPresented = false
    @State private var sunburstRevealProgress = 0.0
    @State private var summaryBarProgress = 0.0
    @State private var animationGeneration = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        Text("storage.heading")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .padding(.bottom, -16)

                        folderCard
                        statusCard

                        if let summary = viewModel.summary {
                            if let fileTree = viewModel.fileTree, fileTree.byteCount > 0 {
                                sunburstCard(root: fileTree)
                            }

                            summaryCard(summary)

                            if !viewModel.files.isEmpty {
                                NavigationLink {
                                    ScannedFilesView(viewModel: viewModel)
                                } label: {
                                    Label("Review and Delete Files", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accentPrimary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, -24)
                    .padding(.bottom, 24)
                }
                .appSoftScrollEdge()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Choose Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("storage.chooseFolder.toolbar")
                }
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
        .onAppear {
            if isTabActive {
                viewModel.loadIfNeeded()
            }
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: isTabActive) { _, isActive in
            if isActive {
                viewModel.loadIfNeeded()
                animateStorageDashboardIfNeeded()
            } else {
                resetStorageAnimations()
            }
        }
        .onChange(of: viewModel.summary) { _, _ in
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: themeSettings.interfaceAnimationsEnabled) { _, _ in
            animateStorageDashboardIfNeeded()
        }
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accentPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzed Folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.selectedDirectoryName ?? "No folder selected")
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                Button("Choose") {
                    isImporterPresented = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("storage.chooseFolder.card")
            }

            if viewModel.state.isScanning {
                Button("Cancel Scan", role: .cancel) {
                    viewModel.cancelScan()
                }
                .buttonStyle(.bordered)
            }
        }
        .storageCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storage.status")
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

            if viewModel.isRestoringStoredFiles {
                ProgressView()
                    .tint(theme.accentPrimary)
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                switch viewModel.state {
                case .idle:
                    Label("Choose a folder to begin scanning.", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                case .scanning(let progress):
                    ProgressView()
                        .tint(theme.accentPrimary)
                    Text("Scanned \(progress.scannedFileCount) files")
                        .foregroundStyle(.secondary)
                case .success:
                    Label("Scan completed.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.accentPrimary)
                case .empty:
                    Label("No readable files found.", systemImage: "folder")
                        .foregroundStyle(.secondary)
                case .partialFailure(_, let skippedFileCount):
                    Label(
                        "Scan completed with \(skippedFileCount) inaccessible file(s).",
                        systemImage: "exclamationmark.triangle"
                    )
                case .cancelled:
                    Label("Scan cancelled.", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "xmark.circle")
                        .foregroundStyle(theme.negativeRed)
                }
            }
        }
        .storageCard()
    }

    /// 封装 `sunburstCard` 对应的局部行为，供当前类型在统一入口下复用。
    private func sunburstCard(root: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Folder Map", systemImage: "circle.hexagongrid")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    FolderMapView(root: root)
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentPrimary)
            }

            SunburstChartView(
                root: root,
                revealProgress: sunburstRevealProgress
            )
                .frame(height: 300)
        }
        .storageCard()
    }

    /// 封装 `summaryCard` 对应的局部行为，供当前类型在统一入口下复用。
    private func summaryCard(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Summary")
                .font(.title2.bold())

            HStack(spacing: 20) {
                metric(title: "Files", value: "\(summary.fileCount)")
                metric(title: "Analyzed", value: byteCountText(summary.totalBytes))
            }

            if summary.unknownByteCountFileCount > 0 {
                Label(
                    "Size unavailable for \(summary.unknownByteCountFileCount) iCloud file(s)",
                    systemImage: "icloud"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(summary.nonEmptyCategories) { category in
                NavigationLink {
                    ScannedFilesView(viewModel: viewModel, category: category.category)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: categorySymbol(category.category))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(storageColor(category.category))
                            .frame(width: 30, height: 30)
                            .background(
                                storageColor(category.category).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(category.category.displayName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(theme.textPrimary)
                                Spacer(minLength: 8)
                                Text(byteCountText(category.byteCount))
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .foregroundStyle(theme.textSecondary)
                            }

                            storageCategoryBar(category)

                            HStack {
                                Text(fileCountText(category.fileCount))
                                    .font(.caption)
                                    .foregroundStyle(theme.textTertiary)
                                Spacer()
                                if category.unknownByteCount > 0 {
                                    Image(systemName: "icloud")
                                        .font(.caption2)
                                        .foregroundStyle(theme.textTertiary)
                                        .accessibilityLabel("Size unavailable for some iCloud files")
                                }
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .storageCard()
    }

    /// 封装 `metric` 对应的局部行为，供当前类型在统一入口下复用。
    private func metric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 封装 `storageColor` 对应的局部行为，供当前类型在统一入口下复用。
    private func storageColor(_ category: FileCategory) -> Color {
        StorageVisualizationPalette.color(for: category)
    }

    /// 解析 `categorySymbol` 对应的业务语义，并返回稳定的分类或映射结果。
    private func categorySymbol(_ category: FileCategory) -> String {
        switch category {
        case .video: "film"
        case .image: "photo"
        case .audio: "music.note"
        case .document: "doc.text"
        case .pdf: "doc.richtext"
        case .archive: "archivebox"
        case .other: "ellipsis"
        }
    }

    /// 封装 `storageCategoryBar` 对应的局部行为，供当前类型在统一入口下复用。
    private func storageCategoryBar(_ category: StorageCategorySummary) -> some View {
        GeometryReader { proxy in
            let naturalWidth = proxy.size.width
                * category.percentage
                * summaryBarProgress
            let minimumVisibleWidth = category.byteCount > 0
                ? 5 * summaryBarProgress
                : 0
            let fillWidth = max(naturalWidth, minimumVisibleWidth)
            let color = storageColor(category.category)

            Capsule()
                .fill(theme.divider.opacity(0.45))
                .overlay(alignment: .leading) {
                    ZStack {
                        LinearGradient(
                            colors: [
                                color.opacity(0.66),
                                color.opacity(0.76),
                                color.opacity(0.70)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        Color.black.opacity(0.10)

                        StorageBarStripeTexture()
                            .blendMode(.softLight)

                        LinearGradient(
                            colors: [.white.opacity(0.07), .clear, .black.opacity(0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(width: fillWidth)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                }
                .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    /// 启动 `animateStorageDashboardIfNeeded` 动画，并确保展示状态与当前页面生命周期一致。
    private func animateStorageDashboardIfNeeded() {
        guard isTabActive, viewModel.summary != nil else { return }
        animationGeneration += 1
        let generation = animationGeneration
        sunburstRevealProgress = 0
        summaryBarProgress = 0

        guard themeSettings.interfaceAnimationsEnabled, !reduceMotion else {
            sunburstRevealProgress = 1
            summaryBarProgress = 1
            return
        }

        Task { @MainActor in
            // Render the empty tracks and closed fan before starting both animations.
            await Task.yield()
            guard isTabActive, generation == animationGeneration else { return }

            // The chart itself has a bounded visible depth, so animation setup
            // must not walk the complete persisted hierarchy on MainActor.
            let sunburstDuration = 0.82

            withAnimation(.easeOut(duration: sunburstDuration)) {
                sunburstRevealProgress = 1
            }
            withAnimation(
                .spring(duration: 0.48, bounce: 0.12)
                    .delay(sunburstDuration * 0.15)
            ) {
                summaryBarProgress = 1
            }
        }
    }

    /// 重置 `resetStorageAnimations` 管理的状态，避免旧任务或旧数据影响下一次操作。
    private func resetStorageAnimations() {
        animationGeneration += 1
        sunburstRevealProgress = 0
        summaryBarProgress = 0
    }

    /// 处理 `handleImport` 输入，并根据结果推进当前业务状态。
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                viewModel.reportSelectionFailure()
                return
            }
            viewModel.scan(directory: url)
        case .failure(let error):
            viewModel.reportSelectionFailure(error: error)
        }
    }

    /// 计算 `byteCountText` 所需的派生值，避免展示层重复实现相同规则。
    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// 计算 `fileCountText` 所需的派生值，避免展示层重复实现相同规则。
    private func fileCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(AppL10n.string("%lld files"), Int64(count))
    }
}

/// 定义 `StorageBarStripeTexture` 的值语义数据与相关行为。
private struct StorageBarStripeTexture: View {
    private let stripePattern: [(position: CGFloat, width: CGFloat, opacity: Double)] = [
        (0.46, 0.8, 0.08), (0.55, 1.0, 0.10), (0.61, 0.6, 0.07),
        (0.67, 1.2, 0.11), (0.72, 0.7, 0.08), (0.76, 1.0, 0.10),
        (0.80, 0.6, 0.07), (0.84, 1.3, 0.12), (0.88, 0.7, 0.08),
        (0.91, 1.0, 0.10), (0.94, 0.6, 0.07), (0.97, 1.1, 0.11)
    ]

    var body: some View {
        Canvas { context, size in
            for (index, stripe) in stripePattern.enumerated() {
                let x = size.width * stripe.position
                let rect = CGRect(
                    x: x,
                    y: 0,
                    width: stripe.width,
                    height: size.height
                )
                let shade = index.isMultiple(of: 3)
                    ? Color.black.opacity(stripe.opacity * 0.55)
                    : Color.white.opacity(stripe.opacity)
                context.fill(Path(rect), with: .color(shade))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 定义 `FolderMapView` 的值语义数据与相关行为。
private struct FolderMapView: View {
    let root: FileNode

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap a folder segment to drill down. Tap the center to go back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SunburstChartView(root: root)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
        }
        .appSoftScrollEdge()
        .background(AppBackground())
        .navigationTitle("Folder Map")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 定义 `ScannedFilesView` 的值语义数据与相关行为。
private struct ScannedFilesView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var viewModel: FileScannerViewModel
    let category: FileCategory?
    @State private var selectedURLs = Set<URL>()
    @State private var isDeleteConfirmationPresented = false

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
    init(viewModel: FileScannerViewModel, category: FileCategory? = nil) {
        self.viewModel = viewModel
        self.category = category
    }

    private var displayedFiles: [ScannedFile] {
        let filteredFiles = if let category {
            viewModel.files.filter { $0.category == category }
        } else {
            viewModel.files
        }
        return FileDisplayOrder.bySizeDescending(filteredFiles)
    }

    var body: some View {
        Group {
            if displayedFiles.isEmpty, viewModel.isRestoringStoredFiles {
                ProgressView("Loading…")
            } else if displayedFiles.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("No scanned files are available.")
                )
            } else {
                List(displayedFiles) { file in
                    Button {
                        if selectedURLs.contains(file.url) {
                            selectedURLs.remove(file.url)
                        } else {
                            selectedURLs.insert(file.url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedURLs.contains(file.url)
                                ? "checkmark.circle.fill"
                                : "circle")
                                .foregroundStyle(
                                    selectedURLs.contains(file.url)
                                        ? theme.accentPrimary
                                        : .secondary
                                )
                            Image(systemName: "doc")
                                .foregroundStyle(theme.fileCategoryColor(file.category))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name)
                                    .lineLimit(1)
                                Text(file.relativePathComponents.dropLast().joined(separator: "/"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: file.byteCount,
                                countStyle: .file
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.cardSurface)
                }
                .scrollContentBackground(.hidden)
                .background(AppBackground())
                .appSoftScrollEdge()
            }
        }
        .navigationTitle(category?.displayName ?? AppL10n.string("Scanned Files"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selectedURLs.count == displayedFiles.count ? "Deselect All" : "Select All") {
                    if selectedURLs.count == displayedFiles.count {
                        selectedURLs.removeAll()
                    } else {
                        selectedURLs = Set(displayedFiles.map(\.url))
                    }
                }
                .disabled(displayedFiles.isEmpty || viewModel.deletionState.isDeleting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedURLs.count) selected")
                        .font(.subheadline.weight(.semibold))
                    Text(selectedFileSizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    if viewModel.deletionState.isDeleting {
                        ProgressView()
                    } else {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .buttonStyle(.glass)
                .foregroundStyle(theme.negativeRed)
                .disabled(selectedURLs.isEmpty || viewModel.deletionState.isDeleting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .alert("Permanently delete selected files?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let urls = selectedURLs
                Task {
                    await viewModel.deleteFiles(withURLs: urls)
                    selectedURLs.formIntersection(Set(displayedFiles.map(\.url)))
                }
            }
        } message: {
            Text("These \(selectedURLs.count) file(s) may not be recoverable. This action cannot be undone in CleanMyIPhone.")
        }
        .alert(
            deletionResultTitle ?? "",
            isPresented: Binding(
                get: { deletionResultTitle != nil },
                set: { if !$0 { viewModel.clearDeletionResult() } }
            )
        ) {
            Button("OK") { viewModel.clearDeletionResult() }
        } message: {
            Text(deletionResultMessage)
        }
    }

    private var deletionResultTitle: String? {
        switch viewModel.deletionState {
        case .success: AppL10n.string("Deletion Complete")
        case .partialFailure: AppL10n.string("Deletion Partly Completed")
        case .failure: AppL10n.string("Deletion Failed")
        default: nil
        }
    }

    private var selectedFileSizeText: String {
        let byteCount = displayedFiles.reduce(Int64.zero) { total, file in
            selectedURLs.contains(file.url) && file.hasKnownByteCount
                ? total + file.byteCount
                : total
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private var deletionResultMessage: String {
        switch viewModel.deletionState {
        case .success(let count):
            String.localizedStringWithFormat(AppL10n.string("%lld file(s) deleted."), Int64(count))
        case .partialFailure(let deletedCount, let failedCount):
            String.localizedStringWithFormat(
                AppL10n.string("%1$lld file(s) deleted; %2$lld could not be deleted."),
                Int64(deletedCount),
                Int64(failedCount)
            )
        case .failure(let error):
            error.localizedDescription
        default:
            ""
        }
    }
}

/// 扩展 `View`，集中实现当前文件所需的附加能力。
private extension View {
    /// 封装 `storageCard` 对应的局部行为，供当前类型在统一入口下复用。
    func storageCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard()
    }
}
