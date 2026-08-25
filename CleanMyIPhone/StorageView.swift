//
//  StorageView.swift
//  CleanMyIPhone
//

import SwiftUI
import UniformTypeIdentifiers

struct StorageView: View {
    @ObservedObject var viewModel: FileScannerViewModel
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        folderCard
                        statusCard

                        if let summary = viewModel.summary {
                            if let fileTree = viewModel.fileTree, fileTree.byteCount > 0 {
                                sunburstCard(root: fileTree)
                            }

                            summaryCard(summary)

                            if !viewModel.largestFiles.isEmpty {
                                largestFilesCard
                            }

                            if !viewModel.files.isEmpty {
                                NavigationLink {
                                    ScannedFilesView(viewModel: viewModel)
                                } label: {
                                    Label("Review and Delete Files", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accentPrimary)
                            }
                        }
                    }
                    .padding()
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            .navigationTitle("Storage")
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
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accentPrimary)

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
                    .tint(AppTheme.accentPrimary)
                Text("Scanned \(progress.scannedFileCount) files")
                    .foregroundStyle(.secondary)
            case .success:
                Label("Scan completed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accentPrimary)
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
                    .foregroundStyle(.red)
            }
        }
        .storageCard()
    }

    private func sunburstCard(root: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folder Map")
                    .font(.headline)
                Spacer()
                Image(systemName: "circle.hexagongrid")
                    .foregroundStyle(AppTheme.accentPrimary)
            }

            SunburstChartView(root: root)
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
                VStack(spacing: 6) {
                    HStack {
                        Circle()
                            .fill(AppTheme.fileCategoryColor(category.category))
                            .frame(width: 9, height: 9)
                        Text(category.category.displayName)
                        Text("\(category.fileCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(byteCountText(category.byteCount))
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: category.percentage)
                        .tint(AppTheme.fileCategoryColor(category.category))
                }
            }
        }
        .storageCard()
    }

    private var largestFilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Largest Files")
                .font(.headline)

            ForEach(viewModel.largestFiles) { file in
                HStack(spacing: 10) {
                    Image(systemName: "doc")
                        .foregroundStyle(AppTheme.fileCategoryColor(file.category))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                        Text(file.category.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(byteCountText(file.byteCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

private struct ScannedFilesView: View {
    @ObservedObject var viewModel: FileScannerViewModel
    @State private var selectedURLs = Set<URL>()
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Group {
            if viewModel.files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "folder",
                    description: Text("No scanned files are available.")
                )
            } else {
                List(viewModel.files) { file in
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
                                        ? AppTheme.accentPrimary
                                        : .secondary
                                )
                            Image(systemName: "doc")
                                .foregroundStyle(AppTheme.fileCategoryColor(file.category))
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
                }
            }
        }
        .navigationTitle("Scanned Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(selectedURLs.count == viewModel.files.count ? "Deselect All" : "Select All") {
                    if selectedURLs.count == viewModel.files.count {
                        selectedURLs.removeAll()
                    } else {
                        selectedURLs = Set(viewModel.files.map(\.url))
                    }
                }
                .disabled(viewModel.files.isEmpty || viewModel.deletionState.isDeleting)
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
                .foregroundStyle(.red)
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
        let byteCount = viewModel.files.reduce(Int64.zero) { total, file in
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
            .appGlassCard()
    }
}
