// 媒体压缩页面。
// 展示准备进度、选择、确认以及批次结果；压缩和原件替换由状态对象及服务执行。
// 页面按分类展示媒体和空间估算，延迟加载可见网格，并提供选择与进度反馈。
// 用户确认前不会发起压缩；权益检查与任务取消通过状态对象和共享访问策略协调。

import SwiftUI
import ImageFormatConversionKit

/// 展示压缩目录、选择和确认状态，并将批次执行交给压缩状态对象。
struct MediaCompressionView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator
    @EnvironmentObject private var accessStore: PremiumFeatureAccessStore
    @ObservedObject var library: PhotoLibraryViewModel
    @StateObject private var model: MediaCompressionViewModel
    @State private var showsPremium = false
    @State private var preparationAttempt = 0

    /// 连接相册，并为当前媒体分类创建独立的压缩状态对象。
    init(category: MediaCompressionCategory, library: PhotoLibraryViewModel) {
        self.library = library
        _model = StateObject(wrappedValue: MediaCompressionViewModel(category: category, library: library))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("compression.explanation").font(.footnote).foregroundStyle(.secondary)
                if let error = model.preparationError {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { preparationAttempt += 1 }
                } else if model.isPreparing && model.visibleLiveItems.isEmpty && model.visiblePhotoItems.isEmpty {
                    ProgressView("Loading media…")
                } else if !model.isPreparing && model.items.isEmpty {
                    ContentUnavailableView("compression.empty", systemImage: model.category.symbol)
                        .accessibilityIdentifier("media.compression.empty")
                } else if model.category == .image {
                    let liveItems = model.visibleLiveItems
                    let photoItems = model.visiblePhotoItems
                    if !liveItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Live Photos", systemImage: "livephoto").font(.headline)
                            mediaGrid(liveItems)
                        }
                        .accessibilityIdentifier("media.compression.liveSection")
                    }
                    if !photoItems.isEmpty {
                        if !liveItems.isEmpty { Text("Photos").font(.headline) }
                        mediaGrid(photoItems)
                    }
                } else {
                    mediaGrid(model.visibleLiveItems + model.visiblePhotoItems)
                }
            }
            .padding(12)
        }
        .background { AppBackground() }
        .navigationTitle(LocalizedStringKey(model.category.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.allSelected ? "Deselect All" : "Select All") { model.toggleAll() }
                    .disabled(model.isProcessing || model.isPreparing || model.items.isEmpty)
                    .accessibilityIdentifier("media.compression.selectAll")
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .task(id: preparationAttempt) { await model.prepare() }
        .sheet(isPresented: $model.isConfirmationPresented, onDismiss: { model.cancelConfirmation() }) {
            compressionConfirmation
        }
        .sheet(isPresented: $showsPremium) { PremiumSubscriptionView(requiredFeature: .imageConversion) }
        .onAppear { tabBarVisibility.setHidden(true, source: "media.compression", scope: .media) }
        .onDisappear {
            model.cancelConfirmation()
            model.cancel()
            tabBarVisibility.setHidden(false, source: "media.compression", scope: .media)
        }
    }

    private var compressionConfirmation: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("compression.confirm.title")
                        .appTypeface(.title3.bold(), size: 20, relativeTo: .title3, weight: .bold)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(format: NSLocalizedString("compression.confirm.message", comment: ""), model.pendingCount))
                        .appTypeface(.body, size: 17, relativeTo: .body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Button(role: .cancel) { model.cancelConfirmation() } label: {
                    Text("Cancel")
                        .appTypeface(.headline.bold(), size: 17, relativeTo: .headline, weight: .bold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.textPrimary.opacity(0.08), in: Capsule())
                }
                .accessibilityIdentifier("media.compression.confirm.cancel")
                Button {
                    if model.category == .video || accessStore.allows(.imageConversion) { model.confirmCompression() }
                    else { model.cancelConfirmation(); showsPremium = true }
                } label: {
                    Text("compression.confirm.action")
                        .appTypeface(.headline.bold(), size: 17, relativeTo: .headline, weight: .bold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.accentPrimary.opacity(0.2), in: Capsule())
                }
                .accessibilityIdentifier("media.compression.confirm.accept")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.textPrimary)
        .padding(24)
        .padding(.top, 12)
        .presentationBackground(theme.cardSurface)
        .presentationDetents([.height(280), .medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 以惰性网格展示项目，在末尾项目出现时请求显示下一批。
    private func mediaGrid(_ items: [MediaCompressionItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                tile(item).onAppear { model.revealMore(after: item) }
            }
        }
        .accessibilityIdentifier("media.compression.grid")
    }

    /// 展示项目缩略图、选择与处理状态，并在允许时切换选择。
    private func tile(_ item: MediaCompressionItem) -> some View {
        Button { model.toggle(item.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { GeometryReader { proxy in
                        MediaAssetThumbnailView(assetID: thumbnailID(item), viewModel: library)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: model.states[item.id]?.isFinished == true ? "checkmark.seal.fill" :
                                model.isSelected(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, theme.accentPrimary)
                            .padding(8).background(.black.opacity(0.25), in: Circle()).padding(5)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: item.isLivePhoto ? "livephoto" : model.category.symbol).foregroundStyle(.white)
                            .padding(7).background(.black.opacity(0.5), in: Capsule()).padding(6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(sizeLabel(item))
                    .appTypeface(.body.weight(.semibold), size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let state = model.states[item.id] { status(state) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .disabled(model.isProcessing || model.isPreparing || model.states[item.id]?.isFinished == true)
        .accessibilityLabel(Text(sizeLabel(item)))
        .accessibilityValue(model.isSelected(item.id) ? Text("Selected") : Text("Not selected"))
    }

    @ViewBuilder private func status(_ state: MediaCompressionItemState) -> some View {
        switch state {
        case .processing: ProgressView().controlSize(.small)
        case .saved: Text("compression.saved").font(.caption).foregroundStyle(.secondary)
        case .replaced: Text("compression.replaced").font(.caption).foregroundStyle(.secondary)
        case .noReduction: Text("compression.noReduction").font(.caption).foregroundStyle(.secondary)
        case .failed(let error): Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        case .cancelled: Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 已完成项目使用实际大小，其余展示压缩前大小与估算结果。
    private func sizeLabel(_ item: MediaCompressionItem) -> String {
        switch model.states[item.id] {
        case let .saved(original, output), let .replaced(original, output): "\(bytes(original)) → \(bytes(output))"
        case let .noReduction(original): "\(bytes(original)) → \(bytes(original))"
        default: "\(bytes(item.originalBytes)) → \(bytes(item.estimatedBytes))"
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if model.isPreparing {
                ProgressView("Loading media…")
            } else if model.isProcessing {
                if case let .processing(completed, total) = model.phase {
                    ProgressView(value: Double(completed), total: Double(total))
                    Text("\(completed) / \(total)").font(.caption).monospacedDigit()
                }
                if model.phase == .replacing {
                    ProgressView("compression.replacing")
                }
                Button(model.phase == .cancelling ? "compression.cancelling" : "Cancel") { model.cancel() }
                    .disabled(model.phase == .cancelling || model.phase == .replacing)
            } else {
                if model.hasBatchResult {
                    Text(String(format: NSLocalizedString("compression.summary", comment: ""), model.savedCount, model.failedCount))
                        .font(.footnote).accessibilityIdentifier("media.compression.summary")
                    if model.phase == .cancelled { Text("Cancelled").font(.footnote) }
                }
                if let error = model.replacementError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("media.compression.replacementError")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        savingsSummary
                        Spacer(minLength: 8)
                        compressionButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        savingsSummary
                        compressionButton.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.textPrimary, lineWidth: 2.5)
                }
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.textPrimary).offset(x: 4, y: 4)
                }
                if model.category != .video && !accessStore.allows(.imageConversion) {
                    Text("Premium").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var savingsSummary: some View {
        Text("\(bytes(model.selectedSizeSummary.original)) → \(bytes(model.selectedSizeSummary.output))")
            .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(String(format: NSLocalizedString("compression.selection.savings", comment: ""), bytes(model.selectedSizeSummary.savings))))
            .accessibilityIdentifier("media.compression.selectionSizes")
    }

    private var compressionButton: some View {
        ConversionActionButton(
            title: NSLocalizedString("compression.action.short", comment: ""),
            accentColor: theme.accentPrimary,
            foregroundColor: theme.textPrimary
        ) {
            if model.category == .video || accessStore.allows(.imageConversion) { model.requestCompression() }
            else { showsPremium = true }
        }
        .frame(minHeight: 44)
        .disabled(model.pendingCount == 0)
        .opacity(model.pendingCount == 0 ? 0.48 : 1)
        .accessibilityIdentifier("media.compression.start")
    }

    /// 可用时展示已保存副本，否则继续使用原资源缩略图。
    private func thumbnailID(_ item: MediaCompressionItem) -> String {
        if let id = model.copyAssetIDs[item.id], library.asset(withIdentifier: id) != nil { return id }
        return item.id
    }

    /// 按文件大小格式化字节数。
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
