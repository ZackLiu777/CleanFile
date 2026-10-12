import Foundation
import Testing
@testable import CleanMyIPhone

@Suite("Media category batch compression")
@MainActor
struct MediaCompressionTests {
    @Test("A compression request and cancellation never invoke the encoder")
    func confirmationProtectsStart() async {
        let recorder = CompressionRecorder()
        let model = MediaCompressionViewModel(category: .video, items: [
            MediaCompressionItem(id: "safe", originalBytes: 1000, estimatedBytes: 500, isExactOriginal: true)
        ], replaceOriginals: { $0 }) { id, _ in try await recorder.compress(id) }
        model.requestCompression()
        #expect(model.isConfirmationPresented)
        #expect(model.phase == .idle)
        #expect(await recorder.calls.isEmpty)
        model.cancelConfirmation()
        #expect(model.confirmCompression() == nil)
        #expect(await recorder.calls.isEmpty)
        model.requestCompression()
        await model.confirmCompression()?.value
        #expect(await recorder.calls == ["safe"])
        #expect(model.confirmCompression() == nil)
    }

    @Test("Large catalogs only expose a bounded first page while selection covers every item", arguments: [100_000, 500_000])
    func largeCatalogPagination(count: Int) async {
        let model = MediaCompressionViewModel(category: .image, preparation: { preview in
            try await Task.detached {
                let items = (0..<count).map {
                    MediaCompressionItem(id: String($0), originalBytes: 1000, estimatedBytes: 500, isExactOriginal: false)
                }
                return MediaCompressionCatalog(items: items)
            }.value
        })
        #expect(model.items.isEmpty)
        #expect(model.isPreparing)
        model.requestCompression()
        #expect(!model.isConfirmationPresented)
        await model.prepare()
        #expect(model.visiblePhotoItems.count == 120)
        #expect(model.pendingCount == count)
        #expect(model.selectedSizeSummary.savings == Int64(count) * 500)
        model.toggle(String(count - 1))
        #expect(model.pendingCount == count - 1)
        #expect(!model.isSelected(String(count - 1)))
        model.toggleAll()
        #expect(model.allSelected)
        model.toggleAll()
        #expect(model.pendingCount == 0)
        #expect(model.selectedSizeSummary.savings == 0)
        if let last = model.visiblePhotoItems.last { model.revealMore(after: last) }
        #expect(model.visiblePhotoItems.count == 240)
    }

    @Test("Cancelling preparation cannot turn a partial preview into a compression batch")
    func cancelledPreparationDoesNotEnableBatch() async {
        let signal = CompressionStartSignal()
        let model = MediaCompressionViewModel(category: .image, preparation: { preview in
            await preview([MediaCompressionItem(id: "preview", originalBytes: 1000, estimatedBytes: 500, isExactOriginal: false)])
            await signal.started("preview")
            try await Task.sleep(for: .seconds(60))
            return MediaCompressionCatalog(items: [])
        })
        let preparation = Task { await model.prepare() }
        await signal.waitUntilStarted()
        #expect(model.visiblePhotoItems.count == 1)
        #expect(model.pendingCount == 0)
        #expect(model.start() == nil)
        preparation.cancel()
        await preparation.value
        #expect(model.items.isEmpty)
        model.requestCompression()
        #expect(!model.isConfirmationPresented)
    }

    @Test("Actual saved sizes replace estimates and remain correct when retrying replacement")
    func actualSavingsAfterRefusedReplacement() async {
        let model = MediaCompressionViewModel(category: .image, items: [
            MediaCompressionItem(id: "saved", originalBytes: 1000, estimatedBytes: 500, isExactOriginal: false)
        ], replaceOriginals: { _ in throw CocoaError(.fileWriteNoPermission) }) { _, _ in
            .saved(original: 2000, output: 600)
        }
        await model.start()?.value
        #expect(model.selectedSizeSummary.original == 2000)
        #expect(model.selectedSizeSummary.output == 600)
        model.toggleAll()
        #expect(model.selectedSizeSummary.savings == 0)
        model.toggleAll()
        #expect(model.selectedSizeSummary.savings == 1400)
    }

    @Test("Selection totals update and never predict negative savings")
    func selectedSizeTotals() {
        let model = MediaCompressionViewModel(category: .image, items: [
            MediaCompressionItem(id: "live", originalBytes: 1000, estimatedBytes: 600, isExactOriginal: false, isLivePhoto: true),
            MediaCompressionItem(id: "image", originalBytes: 200, estimatedBytes: 300, isExactOriginal: true)
        ])
        #expect(model.selectedSizeSummary.original == 1200)
        #expect(model.selectedSizeSummary.output == 800)
        #expect(model.selectedSizeSummary.savings == 400)
        model.toggle("live")
        #expect(model.selectedSizeSummary.original == 200)
        #expect(model.selectedSizeSummary.savings == 0)
        model.toggle("image")
        #expect(model.selectedSizeSummary.original == 0)
        #expect(model.selectedSizeSummary.output == 0)
    }

    @Test("A category larger than a picker limit runs in order and retries only failures")
    func entireCategoryAndPartialFailure() async {
        let recorder = CompressionRecorder()
        let items = (0..<137).map { MediaCompressionItem(id: String($0), originalBytes: 1000, estimatedBytes: 700, isExactOriginal: true) }
        let model = MediaCompressionViewModel(category: .video, items: items, replaceOriginals: { $0 }) { id, _ in
            try await recorder.compress(id)
        }
        #expect(model.selectedIDs.count == 137)
        await model.start()?.value
        #expect(model.savedCount == 135)
        #expect(model.failedCount == 1)
        #expect(model.pendingIDs == ["5"])
        #expect(await recorder.calls == items.map(\.id))
        #expect(model.states["6"] == .noReduction(original: 1000))
        await model.start()?.value
        #expect(model.savedCount == 136)
        #expect(model.failedCount == 0)
        #expect(await recorder.calls == items.map(\.id) + ["5"])
    }

    @Test("Cancellation stops the batch without starting later assets and permits retry")
    func cancellationStopsFollowingAssets() async {
        let signal = CompressionStartSignal()
        let items = ["first", "second"].map { MediaCompressionItem(id: $0, originalBytes: 1000, estimatedBytes: 700, isExactOriginal: false) }
        let model = MediaCompressionViewModel(category: .live, items: items, replaceOriginals: { $0 }) { id, _ in
            await signal.started(id)
            try await Task.sleep(for: .seconds(60))
            return .saved(original: 1000, output: 700)
        }
        let task = model.start()
        await signal.waitUntilStarted()
        model.cancel()
        await task?.value
        #expect(model.phase == .cancelled)
        #expect(model.states["first"] == .cancelled)
        #expect(model.states["second"] == nil)
        #expect(model.pendingIDs == ["first", "second"])
        #expect(await signal.ids == ["first"])
    }

    @Test("Image batches put Live Photos first and preserve the paired-media compression route")
    func mixedImageBatchPreservesLivePhotos() async {
        let recorder = CompressionRecorder()
        let photo = MediaCompressionItem(id: "still", originalBytes: 1000, estimatedBytes: 700, isExactOriginal: true)
        let live = MediaCompressionItem(id: "live", originalBytes: 2000, estimatedBytes: 1600, isExactOriginal: true, isLivePhoto: true)
        let model = MediaCompressionViewModel(category: .image, items: [photo, live], replaceOriginals: { $0 }) { id, category in
            try await recorder.compress(id, category: category)
        }
        #expect(model.items.map(\.id) == ["live", "still"])
        #expect(model.selectedIDs == ["live", "still"])
        await model.start()?.value
        #expect(await recorder.calls == ["live", "still"])
        #expect(await recorder.categories == [.live, .image])
        #expect(model.savedCount == 2)
    }

    @Test("Only smaller verified saves are passed to one replacement batch")
    func replacementExcludesFailedAndUnchangedItems() async {
        let recorder = CompressionReplacementRecorder()
        let items = ["good", "unchanged", "failed"].map {
            MediaCompressionItem(id: $0, originalBytes: 1000, estimatedBytes: 500, isExactOriginal: true)
        }
        let model = MediaCompressionViewModel(category: .video, items: items,
            replaceOriginals: { try await recorder.replace($0) }) { id, _ in
                await recorder.recordConversion(id)
                if id == "failed" { throw MediaCompressionError.verificationFailed }
                if id == "unchanged" { return .noReduction(original: 1000) }
                return .saved(original: 1000, output: 500)
            }
        await model.start()?.value
        #expect(await recorder.replacementBatches == [["good"]])
        #expect(model.states["good"] == .replaced(original: 1000, output: 500))
        #expect(model.pendingIDs == ["failed"])
        #expect(model.states["unchanged"] == .noReduction(original: 1000))
    }

    @Test("A refused replacement preserves originals and retry does not create duplicate copies")
    func replacementRetryDoesNotRecompress() async {
        let recorder = CompressionReplacementRecorder(failsFirstReplacement: true)
        let items = ["first", "second"].map {
            MediaCompressionItem(id: $0, originalBytes: 1000, estimatedBytes: 500, isExactOriginal: true)
        }
        let model = MediaCompressionViewModel(category: .image, items: items,
            replaceOriginals: { try await recorder.replace($0) }) { id, _ in
                await recorder.recordConversion(id)
                return .saved(original: 1000, output: 500)
            }
        await model.start()?.value
        #expect(model.replacementError != nil)
        #expect(model.pendingIDs == ["first", "second"])
        #expect(model.states["first"] == .saved(original: 1000, output: 500))
        await model.start()?.value
        #expect(model.phase == .finished)
        #expect(model.pendingIDs.isEmpty)
        #expect(await recorder.conversionCalls == ["first", "second"])
        #expect(await recorder.replacementBatches.count == 2)
        #expect(model.states["first"] == .replaced(original: 1000, output: 500))
    }

    @Test("Cancellation after a save does not delete originals")
    func cancellationPreservesSavedOriginal() async {
        let signal = CompressionStartSignal()
        let recorder = CompressionReplacementRecorder()
        let items = ["saved", "waiting"].map {
            MediaCompressionItem(id: $0, originalBytes: 1000, estimatedBytes: 500, isExactOriginal: true)
        }
        let model = MediaCompressionViewModel(category: .video, items: items,
            replaceOriginals: { try await recorder.replace($0) }) { id, _ in
                if id == "waiting" {
                    await signal.started(id)
                    try await Task.sleep(for: .seconds(60))
                }
                return .saved(original: 1000, output: 500)
            }
        let task = model.start()
        await signal.waitUntilStarted()
        model.cancel()
        await task?.value
        #expect(model.phase == .cancelled)
        #expect(model.states["saved"] == .saved(original: 1000, output: 500))
        #expect(model.pendingIDs == ["saved", "waiting"])
        #expect(await recorder.replacementBatches.isEmpty)
    }

    @Test("Unknown and empty sizes never promise savings")
    func missingEstimate() {
        for category in MediaCompressionCategory.allCases {
            #expect(MediaCompressionEstimate.bytes(original: 0, width: 0, height: 0, type: nil, category: category) == 0)
        }
    }
}

private actor CompressionRecorder {
    var calls: [String] = []
    var categories: [MediaCompressionCategory] = []
    func compress(_ id: String, category: MediaCompressionCategory = .video) throws -> MediaCompressionOutcome {
        let firstAttempt = !calls.contains(id)
        calls.append(id)
        categories.append(category)
        if id == "5" && firstAttempt { throw CocoaError(.fileReadNoPermission) }
        if id == "6" { return .noReduction(original: 1000) }
        return .saved(original: 1000, output: 700)
    }
}

private actor CompressionStartSignal {
    var ids: [String] = []
    private var waiter: CheckedContinuation<Void, Never>?
    func started(_ id: String) {
        ids.append(id)
        waiter?.resume()
        waiter = nil
    }
    func waitUntilStarted() async {
        if !ids.isEmpty { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor CompressionReplacementRecorder {
    var conversionCalls: [String] = []
    var replacementBatches: [Set<String>] = []
    let failsFirstReplacement: Bool
    init(failsFirstReplacement: Bool = false) { self.failsFirstReplacement = failsFirstReplacement }
    func recordConversion(_ id: String) { conversionCalls.append(id) }
    func replace(_ ids: Set<String>) throws -> Set<String> {
        replacementBatches.append(ids)
        if failsFirstReplacement && replacementBatches.count == 1 { throw CocoaError(.fileWriteNoPermission) }
        return ids
    }
}
