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

    private func metric(title: String, value: String) -> some View {
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

private extension View {
    func storageCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemBackground).opacity(0.92),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}
