// 存储扫描概览、目录导航与文件选择界面。
// 用户选择来源后由扫描模型提供结果；选择和删除确认保持分离，删除结果可包含部分失败。
// 无可用来源或功能锁定时展示示例概览；真实统计和文件列表来自扫描状态。
// 选择来源与删除操作均经过独立交互，实际文件访问和状态更新由底层模型负责。

//
//  StorageView.swift
//  CleanMyIPhone
//


import SwiftUI
import UniformTypeIdentifiers

/// 展示所选来源的扫描状态、分类汇总和文件详情入口。
struct StorageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var accessStore: PremiumFeatureAccessStore
    @ObservedObject var viewModel: FileScannerViewModel
    let isTabActive: Bool
    var showsCloseButton = false
    @State private var isImporterPresented = false
    @State private var isSourceImporterPresented = false
    @State private var sunburstRevealProgress = 0.0
    @State private var summaryBarProgress = 0.0
    @State private var animationGeneration = 0
    @State private var showsPremium = false

    private var preview: StorageDashboardPreview { StorageDashboardPreview.example }
    private var isStorageLocked: Bool { !accessStore.allows(.storage) }
    private var isPreview: Bool { isStorageLocked || !viewModel.hasSelectedStorageSource }
    private var displayedSummary: StorageSummary? { isPreview ? preview.summary : viewModel.summary }
    private var displayedTree: FileNode? { isPreview ? preview.fileTree : viewModel.fileTree }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        Text("storage.heading")
                            .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .padding(.bottom, -16)

                        folderCard
                        statusCard

                        if let summary = displayedSummary {
                            if let fileTree = displayedTree, fileTree.byteCount > 0 {
                                sunburstCard(root: fileTree)
                            }

                            summaryCard(summary)

                            if isPreview || !viewModel.files.isEmpty {
                                fileDetailsLink {
                                    HStack(spacing: 14) {
                                        Image(systemName: "trash")
                                            .appTypeface(.title2, size: 22, relativeTo: .title2, weight: .regular)
                                            .foregroundStyle(theme.accentPrimary)
                                            .frame(width: 44, height: 44)
                                        Text("Review and Delete Files")
                                            .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .appTypeface(.footnote.weight(.semibold), size: 13, relativeTo: .footnote, weight: .semibold)
                                    }
                                    .foregroundStyle(theme.textPrimary)
                                    .padding(16)
                                    .frame(maxWidth: .infinity, minHeight: 80)
                                    .appContentCard()
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("storage.reviewFiles")
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, -24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .appSoftScrollEdge()
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("storage.close")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        chooseSources()
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                    .accessibilityIdentifier("storage.addSources.toolbar")

                    Button {
                        chooseFolder()
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
            .fileImporter(
                isPresented: $isSourceImporterPresented,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                handleSourceImport(result)
            }
        }
        // Drop any pushed real file list when ownership expires, without touching its saved index.
        .id(isStorageLocked)
        .sheet(isPresented: $showsPremium) {
            PremiumSubscriptionView(requiredFeature: .storage)
        }
        .onAppear {
            if isTabActive, !isStorageLocked {
                viewModel.loadIfNeeded()
            }
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: isTabActive) { _, isActive in
            if isActive {
                if !isStorageLocked { viewModel.loadIfNeeded() }
                animateStorageDashboardIfNeeded()
            } else {
                resetStorageAnimations()
            }
        }
        .onChange(of: displayedSummary) { _, _ in
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: isStorageLocked) { _, locked in
            isImporterPresented = false
            isSourceImporterPresented = false
            if locked {
                viewModel.cancelScan()
            } else if isTabActive {
                viewModel.loadIfNeeded()
            }
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: isPreview) { _, _ in
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
                    .appTypeface(.title2, size: 22, relativeTo: .title2, weight: .regular)
                    .foregroundStyle(theme.accentPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(!isPreview && viewModel.isSourceSelection
                        ? LocalizedStringKey("Analyzed Files")
                        : LocalizedStringKey("Analyzed Folder"))
                        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                        .foregroundStyle(.secondary)
                    Text(isPreview ? preview.fileTree.name : viewModel.selectedDirectoryName ?? "No folder selected")
                        .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                        .lineLimit(1)
                }

                Spacer()

                Button("Choose") {
                    chooseFolder()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("storage.chooseFolder.card")
            }

            Button {
                chooseSources()
            } label: {
                Label("Add Files", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("storage.addSources.card")

            if !isPreview, viewModel.state.isScanning {
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
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)

            // The compact dashboard cache is deliberately published before the
            // full 20k+ file index. Do not replace that usable cached state with
            // a blocking spinner while details restore in the background.
            if isPreview {
                Label(AppL10n.string("storage.preview.title"), systemImage: "hand.tap")
                    .foregroundStyle(theme.accentPrimary)
                    .accessibilityIdentifier("storage.preview.notice")
            } else if viewModel.isRestoringStoredFiles, viewModel.summary == nil {
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

    /// 展示目录旭日图及打开完整目录地图的入口。
    private func sunburstCard(root: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Folder Map", systemImage: "circle.hexagongrid")
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                Spacer()
                NavigationLink {
                    FolderMapView(root: root, isPreview: isPreview)
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentPrimary)
                .accessibilityIdentifier("storage.folderMap.expand")
            }

            SunburstChartView(
                root: root,
                revealProgress: sunburstRevealProgress
            )
                .frame(height: 300)
                .accessibilityIdentifier("storage.sunburst")
        }
        .storageCard()
    }

    /// 展示扫描文件数量、容量和各类型占用概览。
    private func summaryCard(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Summary")
                .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)

            HStack(spacing: 20) {
                metric(title: "Files", value: "\(summary.fileCount)")
                metric(title: "Analyzed", value: byteCountText(summary.totalBytes))
            }

            if summary.unknownByteCountFileCount > 0 {
                Label(
                    "Size unavailable for \(summary.unknownByteCountFileCount) iCloud file(s)",
                    systemImage: "icloud"
                )
                .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                .foregroundStyle(.secondary)
            }

            ForEach(summary.nonEmptyCategories) { category in
                fileDetailsLink(category: category.category) {
                    HStack(spacing: 12) {
                        Image(systemName: categorySymbol(category.category))
                            .appTypeface(.system(size: 15, weight: .semibold), size: 15, relativeTo: .body, weight: .semibold)
                            .foregroundStyle(storageColor(category.category))
                            .frame(width: 30, height: 30)
                            .background(
                                storageColor(category.category).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(category.category.displayName)
                                    .appTypeface(.body.weight(.medium), size: 17, relativeTo: .body, weight: .medium)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer(minLength: 8)
                                Text(byteCountText(category.byteCount))
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .foregroundStyle(theme.textSecondary)
                            }

                            storageCategoryBar(category)

                            HStack {
                                Text(fileCountText(category.fileCount))
                                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                    .foregroundStyle(theme.textTertiary)
                                Spacer()
                                if category.unknownByteCount > 0 {
                                    Image(systemName: "icloud")
                                        .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                                        .foregroundStyle(theme.textTertiary)
                                        .accessibilityLabel("Size unavailable for some iCloud files")
                                }
                            }
                        }

                        Image(systemName: "chevron.right")
                            .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storage.category.\(category.category.rawValue)")
            }
        }
        .storageCard()
    }

    @ViewBuilder
    /// 预览状态引导选择目录；已有扫描结果时打开指定分类的文件列表。
    private func fileDetailsLink<Label: View>(
        category: FileCategory? = nil,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if isPreview {
            Button { chooseFolder() } label: { label() }
        } else {
            NavigationLink {
                ScannedFilesView(viewModel: viewModel, category: category)
            } label: { label() }
        }
    }

    /// 检查存储功能权限后打开目录选择器，否则展示高级功能页面。
    private func chooseFolder() {
        guard !isStorageLocked else {
            showsPremium = true
            return
        }
        isImporterPresented = true
    }

    /// 检查存储功能权限后打开来源选择器，否则展示高级功能页面。
    private func chooseSources() {
        guard !isStorageLocked else {
            showsPremium = true
            return
        }
        isSourceImporterPresented = true
    }

    /// 以标题和值展示一项存储统计指标。
    private func metric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                .foregroundStyle(.secondary)
            Text(value)
                .appTypeface(.title3.weight(.semibold), size: 20, relativeTo: .title3, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 从存储可视化调色板获取文件分类颜色。
    private func storageColor(_ category: FileCategory) -> Color {
        StorageVisualizationPalette.color(for: category)
    }

    /// 为每种文件分类选择系统图标。
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

    /// 按分类占比和动画进度绘制容量条，非零分类保留最小可见宽度。
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

    /// 页面活跃时展开旭日图和容量条；动画禁用时直接显示完成状态，代次用于丢弃过期任务。
    private func animateStorageDashboardIfNeeded() {
        guard isTabActive, displayedSummary != nil else { return }
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

    /// 推进动画代次并重置展开进度，使尚未开始的旧动画失效。
    private func resetStorageAnimations() {
        animationGeneration += 1
        sunburstRevealProgress = 0
        summaryBarProgress = 0
    }

    /// 处理单目录选择结果，将用户取消和选择失败交给扫描模型区分。
    private func handleImport(_ result: Result<[URL], Error>) {
        guard !isStorageLocked else { return }
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

    /// 处理多来源选择结果，并将实际选中的 URL 交给扫描模型。
    private func handleSourceImport(_ result: Result<[URL], Error>) {
        guard !isStorageLocked else { return }
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                viewModel.reportSelectionFailure()
                return
            }
            viewModel.scan(sources: urls)
        case .failure(let error):
            viewModel.reportSelectionFailure(error: error)
        }
    }

    /// 按文件大小格式化字节数。
    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    /// 按照当前语言格式化文件数量。
    private func fileCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(AppL10n.string("%lld files"), Int64(count))
    }
}

/// 为存储容量条绘制重复的细条纹理。
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

/// 展示可交互的目录旭日图及相关说明。
private struct FolderMapView: View {
    let root: FileNode
    let isPreview: Bool
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if isPreview {
                    Label(AppL10n.string("storage.preview.title"), systemImage: "hand.tap")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("storage.preview.notice")
                }
                Text("Tap a folder segment to drill down. Tap the center to go back.")
                    .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                    .foregroundStyle(.secondary)

                SunburstChartView(root: root)
                    .accessibilityIdentifier("storage.sunburst.expanded")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 16)
        }
        .appSoftScrollEdge()
        .background(AppBackground())
        .navigationTitle("Folder Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tabBarVisibility.setHidden(
                true,
                source: "storage.folderMap",
                scope: .storage
            )
        }
        .onDisappear {
            tabBarVisibility.setHidden(
                false,
                source: "storage.folderMap",
                scope: .storage
            )
        }
    }
}

/// 提供扫描文件列表、选择汇总和删除操作入口。
private struct ScannedFilesView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator
    @ObservedObject var viewModel: FileScannerViewModel
    let category: FileCategory?
    @State private var selectedURLs = Set<URL>()
    @State private var selectedKnownByteCount: Int64 = 0
    @State private var isDeleteConfirmationPresented = false
    @State private var displayedFiles: [ScannedFile] = []
    @State private var isPreparingDisplayedFiles = true

    /// 连接扫描状态，并可将文件列表限制为指定分类。
    init(viewModel: FileScannerViewModel, category: FileCategory? = nil) {
        self.viewModel = viewModel
        self.category = category
    }

    var body: some View {
        Group {
            if displayedFiles.isEmpty,
               viewModel.isRestoringStoredFiles || isPreparingDisplayedFiles {
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
                        toggleSelection(of: file)
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
                                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: file.byteCount,
                                countStyle: .file
                            ))
                            .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
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
        .accessibilityIdentifier("storage.fileList")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: FileDisplayRequest(
            filesRevision: viewModel.filesRevision,
            category: category
        )) {
            await prepareDisplayedFiles()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selectedURLs.count == displayedFiles.count ? "Deselect All" : "Select All") {
                    if selectedURLs.count == displayedFiles.count {
                        selectedURLs.removeAll()
                        selectedKnownByteCount = 0
                    } else {
                        selectedURLs = Set(displayedFiles.map(\.url))
                        selectedKnownByteCount = displayedFiles.reduce(into: Int64.zero) {
                            if $1.hasKnownByteCount { $0 += $1.byteCount }
                        }
                    }
                }
                .disabled(displayedFiles.isEmpty || viewModel.deletionState.isDeleting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedURLs.count) selected")
                        .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
                    Text(selectedFileSizeText)
                        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
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
                .appGlassButtonStyle()
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
                    selectedURLs.formIntersection(Set(viewModel.files.map(\.url)))
                    recalculateSelectedKnownByteCount()
                }
            }
        } message: {
            Text("These \(selectedURLs.count) file(s) may not be recoverable. This action cannot be undone in Filevra.")
        }
        .alert(
            deletionResultTitle ?? "",
            isPresented: Binding(
                get: { deletionResultTitle != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    // SwiftUI can write this binding during reconciliation.
                    // Defer publishing model state until that update ends.
                    Task { @MainActor in
                        viewModel.clearDeletionResult()
                    }
                }
            )
        ) {
            Button("OK") { viewModel.clearDeletionResult() }
        } message: {
            Text(deletionResultMessage)
        }
        .onAppear {
            tabBarVisibility.setHidden(
                true,
                source: "storage.scannedFiles",
                scope: .storage
            )
        }
        .onDisappear {
            tabBarVisibility.setHidden(
                false,
                source: "storage.scannedFiles",
                scope: .storage
            )
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

    /// 在后台按分类筛选并按大小排序；取消后不发布结果，再同步有效选择和容量。
    @MainActor
    private func prepareDisplayedFiles() async {
        let sourceFiles = viewModel.files
        let category = category
        isPreparingDisplayedFiles = true

        let worker = Task.detached(priority: .userInitiated) {
            let interval = StoragePerformance.begin("Storage File List Prepare")
            defer { StoragePerformance.end("Storage File List Prepare", id: interval) }
            let filteredFiles = if let category {
                sourceFiles.filter { $0.category == category }
            } else {
                sourceFiles
            }
            return FileDisplayOrder.bySizeDescending(filteredFiles)
        }
        let preparedFiles = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        guard !Task.isCancelled else { return }
        displayedFiles = preparedFiles
        selectedURLs.formIntersection(Set(preparedFiles.map(\.url)))
        recalculateSelectedKnownByteCount()
        isPreparingDisplayedFiles = false
    }

    /// 切换单项选择，并仅对已知大小增量更新所选容量。
    private func toggleSelection(of file: ScannedFile) {
        if selectedURLs.remove(file.url) != nil {
            if file.hasKnownByteCount {
                selectedKnownByteCount -= file.byteCount
            }
        } else {
            selectedURLs.insert(file.url)
            if file.hasKnownByteCount {
                selectedKnownByteCount += file.byteCount
            }
        }
    }

    /// 只汇总已知大小的选中文件，未知大小不会被误报为已知容量。
    private func recalculateSelectedKnownByteCount() {
        selectedKnownByteCount = displayedFiles.reduce(into: Int64.zero) { total, file in
            if selectedURLs.contains(file.url), file.hasKnownByteCount {
                total += file.byteCount
            }
        }
    }

    private var selectedFileSizeText: String {
        ByteCountFormatter.string(fromByteCount: selectedKnownByteCount, countStyle: .file)
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

/// 以文件修订号和分类标识一次列表展示请求，便于识别需要刷新的输入。
private struct FileDisplayRequest: Hashable {
    let filesRevision: Int
    let category: FileCategory?
}

/// 提供存储页面共用的卡片样式。
private extension View {
    /// 为内容添加存储卡片内边距并应用主题样式。
    func storageCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard()
    }
}
