//
//  StorageView.swift
//  CleanMyIPhone
//

import SwiftUI
import UniformTypeIdentifiers

struct StorageView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .padding(.vertical, 16)
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
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
        }
        .onAppear {
            animateStorageDashboardIfNeeded()
        }
        .onChange(of: isTabActive) { _, isActive in
            if isActive {
                animateStorageDashboardIfNeeded()
            } else {
                resetStorageAnimations()
            }
        }
        .onChange(of: viewModel.summary) { _, _ in
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
            }

            if viewModel.state.isScanning {
                Button("Cancel Scan", role: .cancel) {
                    viewModel.cancelScan()
                }
                .buttonStyle(.bordered)
            }
        }
        .storageCard()
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

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
        .storageCard()
    }

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

    private func summaryCard(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Storage Summary")
                .font(.headline)

            HStack(spacing: 12) {
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
                    VStack(spacing: 7) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(theme.fileCategoryColor(category.category))
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.category.displayName)
                                    .foregroundStyle(.primary)
                                Text(fileCountText(category.fileCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(byteCountText(category.byteCount))
                                .foregroundStyle(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        ProgressView(value: category.percentage * summaryBarProgress)
                            .tint(theme.fileCategoryColor(category.category))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .storageCard()
    }

    private func metric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accentPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func animateStorageDashboardIfNeeded() {
        guard isTabActive, viewModel.summary != nil else { return }
        animationGeneration += 1
        let generation = animationGeneration
        sunburstRevealProgress = 0
        summaryBarProgress = 0

        guard !reduceMotion else {
            sunburstRevealProgress = 1
            summaryBarProgress = 1
            return
        }

        Task { @MainActor in
            // Render the empty tracks and closed fan before starting both animations.
            await Task.yield()
            guard isTabActive, generation == animationGeneration else { return }

            withAnimation(.easeInOut(duration: 0.9)) {
                sunburstRevealProgress = 1
            }
            withAnimation(.spring(duration: 0.72, bounce: 0.16)) {
                summaryBarProgress = 1
            }
        }
    }

    private func resetStorageAnimations() {
        animationGeneration += 1
        sunburstRevealProgress = 0
        summaryBarProgress = 0
    }

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

    private func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func fileCountText(_ count: Int) -> String {
        String.localizedStringWithFormat(String(localized: "%lld files"), Int64(count))
    }
}

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

private struct ScannedFilesView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var viewModel: FileScannerViewModel
    let category: FileCategory?
    @State private var selectedURLs = Set<URL>()
    @State private var isDeleteConfirmationPresented = false

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
            if displayedFiles.isEmpty {
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
        .navigationTitle(category?.displayName ?? String(localized: "Scanned Files"))
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
        case .success: String(localized: "Deletion Complete")
        case .partialFailure: String(localized: "Deletion Partly Completed")
        case .failure: String(localized: "Deletion Failed")
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
            String.localizedStringWithFormat(String(localized: "%lld file(s) deleted."), Int64(count))
        case .partialFailure(let deletedCount, let failedCount):
            String.localizedStringWithFormat(
                String(localized: "%1$lld file(s) deleted; %2$lld could not be deleted."),
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

private extension View {
    func storageCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appContentCard()
    }
}
