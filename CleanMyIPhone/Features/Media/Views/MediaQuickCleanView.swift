//
//  MediaQuickCleanView.swift
//  CleanMyIPhone
//

import SwiftUI

struct MediaQuickCleanView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityCoordinator
    @ObservedObject private var photoLibrary: PhotoLibraryViewModel
    @StateObject private var viewModel: MediaQuickCleanViewModel
    @State private var isDeleteConfirmationPresented = false
    @State private var completionMessage: String?
    @State private var presentedCategories: [MediaQuickCleanViewModel.Category]
    @State private var categoryFrames = [MediaQuickCleanViewModel.Category.ID: CGRect]()
    @State private var pendingDeletionCategoryIDs = Set<MediaQuickCleanViewModel.Category.ID>()
    @State private var dissolvingCategoryIDs = Set<MediaQuickCleanViewModel.Category.ID>()
    @State private var isAnimatingDeletion = false
    @State private var categoryScrollPosition: MediaQuickCleanViewModel.Category.ID?

    init(photoLibrary: PhotoLibraryViewModel) {
        self.photoLibrary = photoLibrary
        let quickCleanViewModel = MediaQuickCleanViewModel(photoLibrary: photoLibrary)
        _viewModel = StateObject(
            wrappedValue: quickCleanViewModel
        )
        _presentedCategories = State(initialValue: quickCleanViewModel.categories)
    }

    var body: some View {
        ZStack {
            AppBackground()

            if presentedCategories.isEmpty {
                emptyContent
            } else {
                categoryContent
            }
        }
        .navigationTitle("Quick Cleanup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.allCategoriesSelected ? "Deselect All" : "Select All") {
                    viewModel.toggleAllCategories()
                }
                .disabled(presentedCategories.isEmpty || photoLibrary.deletionState.isDeleting || isAnimatingDeletion)
                .accessibilityIdentifier("media.quickClean.selectAll")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !presentedCategories.isEmpty {
                cleanupBar
            }
        }
        .alert("Delete selected media?", isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let orderedIDs = presentedCategories
                        .map(\.id)
                        .filter { viewModel.selectedCategoryIDs.contains($0) }
                    pendingDeletionCategoryIDs = Set(orderedIDs)
                    isAnimatingDeletion = true
                    await viewModel.deleteSelection()
                    if case .success = photoLibrary.deletionState {
                        // 等待系统 PhotoKit 确认界面完全退场，避免把系统遮罩截入卡片快照。
                        try? await Task.sleep(for: .milliseconds(120))
                        await animateDeletedCategories(in: orderedIDs)
                        handleDeletionResult()
                    } else {
                        pendingDeletionCategoryIDs.removeAll()
                        isAnimatingDeletion = false
                        presentedCategories = viewModel.categories
                    }
                }
            }
        } message: {
            Text(
                "The selected items will move to Recently Deleted and may not free space immediately."
            )
        }
        .alert(
            "Cleanup Complete",
            isPresented: Binding(
                get: { completionMessage != nil },
                set: { if !$0 { completionMessage = nil } }
            )
        ) {
            Button("Done") {
                completionMessage = nil
                photoLibrary.clearDeletionResult()
            }
        } message: {
            if let completionMessage { Text(completionMessage) }
        }
        .alert(
            "Deletion Failed",
            isPresented: Binding(
                get: {
                    if case .failure = photoLibrary.deletionState { return true }
                    return false
                },
                set: { if !$0 { photoLibrary.clearDeletionResult() } }
            )
        ) {
            Button("Done") { photoLibrary.clearDeletionResult() }
        } message: {
            if case .failure(let error) = photoLibrary.deletionState {
                Text(error.localizedDescription)
            }
        }
        .onChange(of: photoLibrary.analysisState) { _, _ in
            viewModel.refreshCategories()
        }
        .onChange(of: viewModel.categories) { _, categories in
            guard !isAnimatingDeletion else { return }
            presentedCategories = categories
        }
        .onPreferenceChange(QuickCleanCategoryFramePreferenceKey.self) { frames in
            categoryFrames = frames
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedCategoryIDs)
        .onAppear {
            tabBarVisibility.setHidden(
                true,
                source: "media.quickClean",
                scope: .media
            )
        }
        .onDisappear {
            tabBarVisibility.setHidden(
                false,
                source: "media.quickClean",
                scope: .media
            )
        }
    }

    private var categoryContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summaryCard

                ForEach(presentedCategories) { category in
                    categoryButton(category)
                        .id(category.id)
                }

                Text("Sizes are approximate. Categories can overlap, and selected items are counted once.")
                    .appTypeface(.footnote, size: 13, relativeTo: .footnote, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .animation(.snappy(duration: 0.32), value: presentedCategories.map(\.id))
        }
        .scrollPosition(id: $categoryScrollPosition, anchor: .center)
        .appSoftScrollEdge()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Review Cleanup Suggestions", systemImage: "sparkles")
                .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                .foregroundStyle(theme.textPrimary)
            Text("Select one or more categories. Similar-photo groups always keep the recommended photo.")
                .foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appContentCard()
    }

    private func categoryButton(_ category: MediaQuickCleanViewModel.Category) -> some View {
        let isSelected = viewModel.isSelected(category)
            || pendingDeletionCategoryIDs.contains(category.id)
        return Button {
            viewModel.toggle(category)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .appTypeface(.title3.weight(.semibold), size: 20, relativeTo: .title3, weight: .semibold)
                    .foregroundStyle(isSelected ? theme.accentPrimary : theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected ? theme.accentPrimary.opacity(0.16) : theme.cardElevated,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                    Text(categoryDetail(category))
                        .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appTypeface(.title2, size: 22, relativeTo: .title2, weight: .regular)
                    .foregroundStyle(isSelected ? theme.accentPrimary : theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard(cornerRadius: 20)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.accentPrimary, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(dissolvingCategoryIDs.contains(category.id) ? 0 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: QuickCleanCategoryFramePreferenceKey.self,
                    value: [category.id: proxy.frame(in: .global)]
                )
            }
        }
        .disabled(isAnimatingDeletion)
        .accessibilityLabel(category.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects or deselects every suggested item in this category.")
        .accessibilityIdentifier("media.quickClean.category.\(category.id.rawValue)")
    }

    private var cleanupBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCountText)
                    .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                Text(estimatedSelectedSizeText)
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                if photoLibrary.deletionState.isDeleting {
                    ProgressView()
                } else {
                    Label("Clean Up", systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.negativeRed)
            .disabled(
                viewModel.selectedAssetIDs.isEmpty
                    || photoLibrary.deletionState.isDeleting
                    || isAnimatingDeletion
            )
            .accessibilityIdentifier("media.quickClean.delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appContentCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label("No Cleanup Suggestions", systemImage: "checkmark.circle")
        } description: {
            Text("Run media analysis first to create safe cleanup categories.")
        } actions: {
            if !photoLibrary.analysisState.isAnalyzing {
                Button("Analyze Media") {
                    photoLibrary.startAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentPrimary)
            } else {
                ProgressView("Analyzing media…")
            }
        }
    }

    private func categoryDetail(_ category: MediaQuickCleanViewModel.Category) -> String {
        let count = String.localizedStringWithFormat(
            AppL10n.string("%lld items"),
            Int64(category.assetIDs.count)
        )
        let size = ByteCountFormatter.string(
            fromByteCount: viewModel.estimatedByteCount(for: category),
            countStyle: .file
        )
        return "\(count) · ~\(size)"
    }

    private var selectedCountText: String {
        String.localizedStringWithFormat(
            AppL10n.string("%lld items selected"),
            Int64(viewModel.selectedAssetIDs.count)
        )
    }

    private var estimatedSelectedSizeText: String {
        let size = ByteCountFormatter.string(
            fromByteCount: viewModel.selectedEstimatedByteCount,
            countStyle: .file
        )
        return String.localizedStringWithFormat(
            AppL10n.string("Approximately %@"),
            size
        )
    }

    private func handleDeletionResult() {
        if case let .success(deletedCount, estimatedBytes) = photoLibrary.deletionState {
            let count = String.localizedStringWithFormat(
                AppL10n.string("%lld items"),
                Int64(deletedCount)
            )
            let size = ByteCountFormatter.string(
                fromByteCount: estimatedBytes,
                countStyle: .file
            )
            completionMessage = String.localizedStringWithFormat(
                AppL10n.string("%@ moved to Recently Deleted · ~%@"),
                count,
                size
            )
        }
    }

    /// 按当前列表顺序逐张分解卡片；每张结束后才收拢布局并处理下一张。
    private func animateDeletedCategories(
        in orderedIDs: [MediaQuickCleanViewModel.Category.ID]
    ) async {
        guard let window = activeWindow else {
            presentedCategories = viewModel.categories
            pendingDeletionCategoryIDs.removeAll()
            isAnimatingDeletion = false
            return
        }

        let usesMotion = themeSettings.interfaceAnimationsEnabled && !reduceMotion
        for categoryID in orderedIDs {
            if categoryFrames[categoryID]?.intersects(window.bounds) != true {
                categoryScrollPosition = categoryID
                try? await Task.sleep(for: .milliseconds(usesMotion ? 300 : 100))
            }

            guard
                presentedCategories.contains(where: { $0.id == categoryID }),
                let frame = categoryFrames[categoryID],
                let snapshot = QuickCleanCardDeletionEffect.capture(frame: frame, in: window)
            else {
                presentedCategories.removeAll { $0.id == categoryID }
                continue
            }

            await QuickCleanCardDeletionEffect.play(
                snapshot: snapshot,
                in: window,
                animated: usesMotion,
                hideOriginal: {
                    dissolvingCategoryIDs.insert(categoryID)
                }
            )

            withAnimation(.snappy(duration: usesMotion ? 0.32 : 0.16)) {
                presentedCategories.removeAll { $0.id == categoryID }
                dissolvingCategoryIDs.remove(categoryID)
            }
            try? await Task.sleep(for: .milliseconds(usesMotion ? 360 : 180))
        }

        categoryScrollPosition = nil
        presentedCategories = viewModel.categories
        pendingDeletionCategoryIDs.removeAll()
        dissolvingCategoryIDs.removeAll()
        isAnimatingDeletion = false
    }

    private var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
