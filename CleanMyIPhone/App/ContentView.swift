// 主导航及外部分享导入的协调入口。
// 该页面在各标签之间共享相册和访问状态，并跟踪不同作用域对标签栏的隐藏请求。
// 主界面承载照片首页，并协调存储、转换及设置页面的呈现。
// 外部文档与分享批次经收件箱交给转换组件；只移除确认导入成功的暂存条目。

//
//  ContentView.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//
 

import ImageFormatConversionKit
import Combine
import StoreKit
import SwiftUI

/// 按页面作用域协调自定义 Tab Bar 的隐藏请求，避免其他标签或嵌套页面影响当前界面。
@MainActor
final class TabBarVisibilityCoordinator: ObservableObject {
    /// 标识独立导航区域，使隐藏请求只影响当前区域。
    enum Scope: String {
        case media
        case storage
        case conversion
        case settings
    }

    @Published private(set) var isHidden = false
    private var activeScope: Scope = .media
    private var hiddenSources = Set<String>()

    /// 切换当前标签作用域并重新计算标签栏可见性。
    func setActiveScope(_ scope: Scope) {
        activeScope = scope
        updateVisibility()
    }

    /// 按来源记录或移除隐藏请求，允许同一作用域内多个页面独立控制。
    func setHidden(_ hidden: Bool, source: String, scope: Scope) {
        let key = "\(scope.rawValue):\(source)"
        if hidden {
            hiddenSources.insert(key)
        } else {
            hiddenSources.remove(key)
        }
        updateVisibility()
    }

    /// 根据当前作用域中是否存在隐藏来源，更新标签栏状态。
    private func updateVisibility() {
        let scopePrefix = "\(activeScope.rawValue):"
        let shouldHide = hiddenSources.contains { $0.hasPrefix(scopePrefix) }
        guard shouldHide != isHidden else { return }
        isHidden = shouldHide
    }
}

/// 组装照片首页及存储、转换、设置入口，并协调外部导入和共享状态。
struct ContentView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject private var accessStore: PremiumFeatureAccessStore
    @StateObject private var tabBarVisibility = TabBarVisibilityCoordinator()
    @StateObject private var mediaViewModel = PhotoLibraryViewModel()
    @StateObject private var fileViewModel = FileScannerViewModel()
    @State private var showsConversion = false
    @State private var showsStorage = false
    @State private var showsSettings = false
    @State private var pendingShareBatch: ShareImportInbox.Batch?
    @State private var activeShareImport: ShareImportRequest?
    @State private var incomingDocumentURLs: [URL] = []
    @State private var documentImportTask: Task<Void, Never>?

    /// 共享权益状态，并向扫描模型注入存储功能权限检查。
    init(accessStore: PremiumFeatureAccessStore) {
        self.accessStore = accessStore
        _fileViewModel = StateObject(wrappedValue: FileScannerViewModel(canUseStorage: {
            accessStore.allows(.storage)
        }))
    }

    var body: some View {
        PhotosView(
            viewModel: mediaViewModel,
            isTabActive: !showsConversion,
            onOpenStorage: { showsStorage = true },
            onOpenSettings: { showsSettings = true },
            onOpenConversion: { showsConversion = true }
        )
        .fullScreenCover(isPresented: $showsConversion, onDismiss: {
            // Unhandled imports stay in the inbox and can be reopened later.
            activeShareImport = nil
        }) {
            ConversionHomeView(
                theme: theme.conversionTheme,
                isTabActive: true,
                animationsEnabled: themeSettings.interfaceAnimationsEnabled,
                shareImport: activeShareImport,
                onShareImportComplete: finishShareImport,
                closeButtonTitle: AppL10n.string("Close"),
                onClose: { showsConversion = false }
            )
        }
        .sheet(isPresented: $showsStorage) {
            StorageView(viewModel: fileViewModel, isTabActive: true, showsCloseButton: true)
                .environmentObject(tabBarVisibility)
                .environmentObject(themeSettings)
                .environmentObject(accessStore)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(showsCloseButton: true)
        }
        .onChange(of: mediaViewModel.deletionState) { _, state in
            // Only a confirmed PhotoKit deletion is a completed cleanup, not a swipe mark.
            if case .success = state, scenePhase == .active {
                requestReview()
            }
        }
        .task {
            showPendingShareBatchIfNeeded()
            // Start loading the Media home when its content appears.
            await mediaViewModel.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { showPendingShareBatchIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanFileShareImportReady)) { _ in
            showPendingShareBatchIfNeeded()
        }
        .onOpenURL { url in
            if url.isFileURL {
                receiveDocument(url)
                return
            }
        }
        .sheet(item: $pendingShareBatch, onDismiss: {
            if activeShareImport != nil { showsConversion = true }
        }) { batch in
            VStack(spacing: 22) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 42))
                    .foregroundStyle(theme.accentPrimary)
                Text("Import to Filevra")
                    .font(.title2.bold())
                Text("Choose what to convert. Originals will remain in Photos.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textSecondary)
                if batch.imageCount > 0 {
                    Button {
                        startShareImport(batch, kind: .image)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Convert Images")
                            Text("(\(batch.imageCount))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if batch.videoCount > 0 {
                    Button {
                        startShareImport(batch, kind: .video)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Convert Videos")
                            Text("(\(batch.videoCount))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Later") { pendingShareBatch = nil }
                    .buttonStyle(.plain)
            }
            .padding(28)
            .presentationDetents([.medium])
        }
        // Wrap every presentation host, so modal destinations inherit the same coordinator.
        .environmentObject(tabBarVisibility)
    }

    /// 合并短时间内多次文档回调，再作为一个分享批次导入。
    private func receiveDocument(_ url: URL) {
        incomingDocumentURLs.append(url)
        documentImportTask?.cancel()
        // SwiftUI may deliver one callback per selected file; coalesce nearby URLs.
        documentImportTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let urls = incomingDocumentURLs
            incomingDocumentURLs.removeAll()
            guard let batch = try? await ShareImportInbox.importDocumentURLs(urls) else { return }
            showPendingShareBatchIfNeeded(preferredID: batch.id)
        }
    }

    /// 空闲时优先处理指定批次；单类型直接导入，混合类型先让用户选择。
    private func showPendingShareBatchIfNeeded(preferredID: UUID? = nil) {
        guard pendingShareBatch == nil, activeShareImport == nil else { return }
        guard let batches = try? ShareImportInbox.batches(),
              let batch = batches.first(where: { $0.id == preferredID }) ?? batches.first else { return }
        if batch.imageCount > 0 && batch.videoCount == 0 {
            startShareImport(batch, kind: .image)
        } else if batch.videoCount > 0 && batch.imageCount == 0 {
            startShareImport(batch, kind: .video)
        } else {
            pendingShareBatch = batch
        }
    }

    /// 仅收集指定类型且仍存在的暂存文件，并协调选择弹窗与转换页面的呈现顺序。
    private func startShareImport(_ batch: ShareImportInbox.Batch, kind: ShareImportInbox.Kind) {
        let files = batch.entries.filter { $0.kind == kind }.compactMap { entry -> ShareImportRequest.File? in
            guard let url = try? ShareImportInbox.fileURL(for: entry, in: batch),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShareImportRequest.File(id: entry.id, url: url)
        }
        guard !files.isEmpty else { return }
        activeShareImport = ShareImportRequest(
            batchID: batch.id, kind: kind == .image ? .image : .video, files: files
        )
        let wasChoosingImportKind = pendingShareBatch != nil
        pendingShareBatch = nil
        // Wait for the mixed-file chooser to dismiss before presenting another modal.
        if !wasChoosingImportKind { showsConversion = true }
    }

    /// 仅移除已成功导入的条目；失败项及其他类型保留在收件箱供后续处理。
    private func finishShareImport(batchID: UUID, importedIDs: Set<UUID>) {
        if let batch = try? ShareImportInbox.batches().first(where: { $0.id == batchID }),
           !importedIDs.isEmpty {
            try? ShareImportInbox.remove(importedIDs, from: batch)
        }
        activeShareImport = nil
        // Any failed or mixed-type files remain in the inbox for a later attempt.
    }

}

/// 将应用主题适配为转换组件使用的主题配置。
extension Theme {
    var conversionTheme: ConversionTheme {
        ConversionTheme(
            background: conversionBackground,
            cardSurface: cardSurface,
            cardElevated: cardElevated,
            cardHighlight: backgroundSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accentPrimary,
            destructive: negativeRed,
            divider: divider,
            liquidGlassEnabled: liquidGlassEnabled,
            liquidGlassCardsEnabled: liquidGlassCardsEnabled
        )
    }

    private var conversionBackground: ConversionBackground {
        switch background {
        case let .solid(color):
            .solid(color)
        case let .linearGradient(stops, startPoint, endPoint):
            .linearGradientStops(
                stops: stops.map {
                    ConversionGradientStop(color: $0.color.color, location: $0.location)
                },
                startPoint: startPoint,
                endPoint: endPoint
            )
        case let .meshGradient(colors):
            .meshGradient(colors: colors)
        }
    }
}

#if DEBUG
// Keep the canvas preview stateless. The live root owns file-scanning and
// PhotoKit state objects that should only be attached by the running app.
#Preview("App Theme") {
    VStack(spacing: 16) {
        Image(systemName: "photo.on.rectangle")
            .appTypeface(.largeTitle, size: 34, relativeTo: .largeTitle, weight: .regular)
            .foregroundStyle(Theme.system.accentPrimary)

        Text("Filevra")
            .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)

        Text("Run the app to choose a folder or access the photo library.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    .padding()
}
#endif
