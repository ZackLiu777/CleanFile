import Combine
import Foundation
import Photos

@MainActor
final class MediaCompressionViewModel: ObservableObject {
    enum Phase: Equatable { case idle, processing(completed: Int, total: Int), replacing, cancelling, finished, cancelled, replacementFailure(String) }
    let category: MediaCompressionCategory
    private var catalog = MediaCompressionCatalog(items: [])
    var items: [MediaCompressionItem] { catalog.items }
    @Published private(set) var visibleLiveItems: [MediaCompressionItem] = []
    @Published private(set) var visiblePhotoItems: [MediaCompressionItem] = []
    @Published private(set) var isPreparing = false
    @Published var isConfirmationPresented = false
    @Published private(set) var preparationError: String?
    @Published private(set) var pendingCount = 0
    @Published private(set) var selectedSizeSummary: (original: Int64, output: Int64, savings: Int64) = (0, 0, 0)
    private var confirmationRequested = false
    private var selectsAll = true
    private var selectionExceptions: Set<String> = []
    private var finishedIDs: Set<String> = []
    private var eligibleOriginal: Int64 = 0
    private var eligibleOutput: Int64 = 0
    private var library: PhotoLibraryViewModel?
    private var hasPrepared = false
    private var preparationGeneration = 0
    typealias Preparation = @Sendable (@escaping @Sendable ([MediaCompressionItem]) async -> Void) async throws -> MediaCompressionCatalog
    private var preparation: Preparation?
    var selectedIDs: Set<String> { Set(items.lazy.filter { self.isSelected($0.id) }.map(\.id)) }
    @Published private(set) var states: [String: MediaCompressionItemState] = [:]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var copyAssetIDs: [String: String] = [:]
    private let onBatchCompletion: @MainActor () -> Void
    private let replaceOriginals: @Sendable (Set<String>) async throws -> Set<String>
    private let operation: @Sendable (String, MediaCompressionCategory) async throws -> MediaCompressionOutcome
    private var task: Task<Void, Never>?

    convenience init(category: MediaCompressionCategory, library: PhotoLibraryViewModel) {
        self.init(category: category, items: [], onBatchCompletion: { library.refresh() })
        self.library = library
        isPreparing = true
    }

    /// The injected loader also allows CI to verify cancellation without a real photo library.
    convenience init(category: MediaCompressionCategory, preparation: @escaping Preparation) {
        self.init(category: category, items: [])
        self.preparation = preparation
        isPreparing = true
    }

    func prepare() async {
        guard !hasPrepared else { return }
        preparationGeneration += 1
        let generation = preparationGeneration
        isPreparing = true
        preparationError = nil
        let loader: Preparation
        if let preparation { loader = preparation }
        else if let library {
            // Array/dictionary snapshots share immutable storage; do not enumerate on the main actor.
            let assets = library.assets
            let exactSizes = library.exactByteCountsByIdentifier
            let classification: MediaClassificationResult?
            switch library.analysisState {
            case .success(let result), .partialFailure(let result): classification = result
            default: classification = nil
            }
            let category = category
            loader = { preview in
                try await MediaCompressionPreparation().prepare(category: category, assets: assets,
                    exactSizes: exactSizes, classification: classification, preview: preview)
            }
        } else { isPreparing = false; hasPrepared = true; return }
        do {
            let prepared = try await loader { [weak self] preview in
                await self?.showPreview(preview, generation: generation)
            }
            try Task.checkCancellation()
            guard generation == preparationGeneration else { return }
            install(prepared)
            hasPrepared = true
            isPreparing = false
        } catch is CancellationError {
            // A later appearance may start a fresh preparation; stale results cannot replace it.
            if generation == preparationGeneration { isPreparing = false }
        } catch {
            if generation == preparationGeneration {
                preparationError = error.localizedDescription
                isPreparing = false
            }
        }
    }

    private func showPreview(_ preview: [MediaCompressionItem], generation: Int) {
        guard generation == preparationGeneration, !Task.isCancelled else { return }
        visibleLiveItems = preview.filter(\.isLivePhoto)
        visiblePhotoItems = preview.filter { !$0.isLivePhoto }
    }

    private func install(_ prepared: MediaCompressionCatalog) {
        catalog = prepared
        eligibleOriginal = prepared.originalBytes
        eligibleOutput = prepared.outputBytes
        pendingCount = prepared.items.count
        selectedSizeSummary = (eligibleOriginal, eligibleOutput, eligibleOriginal - eligibleOutput)
        visibleLiveItems = Array(prepared.liveItems.prefix(120))
        visiblePhotoItems = Array(prepared.photoItems.prefix(120))
    }

    func revealMore(after item: MediaCompressionItem) {
        guard !isPreparing else { return }
        if item.isLivePhoto, item.id == visibleLiveItems.last?.id, visibleLiveItems.count < catalog.liveItems.count {
            visibleLiveItems.append(contentsOf: catalog.liveItems.dropFirst(visibleLiveItems.count).prefix(120))
        } else if !item.isLivePhoto, item.id == visiblePhotoItems.last?.id, visiblePhotoItems.count < catalog.photoItems.count {
            visiblePhotoItems.append(contentsOf: catalog.photoItems.dropFirst(visiblePhotoItems.count).prefix(120))
        }
    }

    init(category: MediaCompressionCategory, items: [MediaCompressionItem],
         onBatchCompletion: @escaping @MainActor () -> Void = {},
         replaceOriginals: (@Sendable (Set<String>) async throws -> Set<String>)? = nil,
         operation: (@Sendable (String, MediaCompressionCategory) async throws -> MediaCompressionOutcome)? = nil) {
        self.onBatchCompletion = onBatchCompletion
        self.category = category
        let service = MediaCompressionService()
        self.replaceOriginals = replaceOriginals ?? { ids in try await service.replaceOriginals(ids) }
        self.operation = operation ?? { id, category in try await service.compress(id: id, category: category) }
        install(MediaCompressionCatalog(items: items))
    }

    var isProcessing: Bool {
        switch phase { case .processing, .replacing, .cancelling: true; default: false }
    }
    var eligibleIDs: Set<String> { Set(catalog.byID.keys).subtracting(finishedIDs) }
    var pendingIDs: Set<String> { selectedIDs }
    var allSelected: Bool { pendingCount > 0 && pendingCount == items.count - finishedIDs.count }
    func isSelected(_ id: String) -> Bool {
        !finishedIDs.contains(id) && (selectsAll != selectionExceptions.contains(id))
    }

    private func sizes(for id: String) -> (Int64, Int64) {
        if case let .saved(original, output) = states[id] { return (max(0, original), min(max(0, original), max(0, output))) }
        guard let index = catalog.byID[id] else { return (0, 0) }
        let item = items[index]
        return (max(0, item.originalBytes), min(max(0, item.originalBytes), max(0, item.estimatedBytes)))
    }

    private func adjustSelection(original: Int64, output: Int64, count: Int) {
        let source = selectedSizeSummary.original + original
        let destination = selectedSizeSummary.output + output
        selectedSizeSummary = (source, destination, source - destination)
        pendingCount += count
    }

    private func setState(_ state: MediaCompressionItemState, for id: String) {
        let selected = isSelected(id)
        let old = sizes(for: id)
        states[id] = state
        if state.isFinished {
            finishedIDs.insert(id)
            eligibleOriginal -= old.0
            eligibleOutput -= old.1
            if selected { adjustSelection(original: -old.0, output: -old.1, count: -1) }
        } else {
            let new = sizes(for: id)
            eligibleOriginal += new.0 - old.0
            eligibleOutput += new.1 - old.1
            if selected { adjustSelection(original: new.0 - old.0, output: new.1 - old.1, count: 0) }
        }
    }
    var savedCount: Int { states.values.filter { switch $0 { case .saved, .replaced: true; default: false } }.count }
    var failedCount: Int { states.values.filter { if case .failed = $0 { true } else { false } }.count }

    var hasBatchResult: Bool {
        switch phase { case .finished, .cancelled, .replacementFailure: true; default: false }
    }
    var replacementError: String? {
        if case .replacementFailure(let message) = phase { return message }
        return nil
    }

    func toggleAll() {
        guard !isProcessing, !isPreparing else { return }
        selectsAll = !allSelected
        selectionExceptions = []
        pendingCount = selectsAll ? items.count - finishedIDs.count : 0
        selectedSizeSummary = selectsAll ? (eligibleOriginal, eligibleOutput, eligibleOriginal - eligibleOutput) : (0, 0, 0)
    }
    func toggle(_ id: String) {
        guard !isProcessing, !isPreparing, catalog.byID[id] != nil, !finishedIDs.contains(id) else { return }
        let sign: Int64 = isSelected(id) ? -1 : 1
        let size = sizes(for: id)
        if !selectionExceptions.insert(id).inserted { selectionExceptions.remove(id) }
        adjustSelection(original: sign * size.0, output: sign * size.1, count: Int(sign))
    }
    func requestCompression() {
        guard !isProcessing, !isPreparing, preparationError == nil, pendingCount > 0 else { return }
        confirmationRequested = true
        isConfirmationPresented = true
    }

    func cancelConfirmation() { confirmationRequested = false; isConfirmationPresented = false }

    @discardableResult
    func confirmCompression() -> Task<Void, Never>? {
        // SwiftUI dismisses the alert binding before executing its action.
        guard confirmationRequested else { return nil }
        confirmationRequested = false
        isConfirmationPresented = false
        return start()
    }

    @discardableResult
    func start() -> Task<Void, Never>? {
        guard !isProcessing, !isPreparing, preparationError == nil else { return nil }
        let pending = pendingIDs
        let batch = items.filter { pending.contains($0.id) }
        guard !batch.isEmpty else { return nil }
        phase = .processing(completed: 0, total: batch.count)
        let operation = operation
        let replaceOriginals = replaceOriginals
        let onBatchCompletion = onBatchCompletion
        let category = category
        task = Task { [weak self] in
            var changedLibrary = false
            for (index, item) in batch.enumerated() {
                guard !Task.isCancelled else { break }
                // Retry the deletion of an already saved copy without encoding it again.
                if case .saved = self?.states[item.id] { continue }
                self?.setState(.processing, for: item.id)
                do {
                    let outcome = try await operation(item.id, item.isLivePhoto ? .live : category)
                    switch outcome {
                    case let .saved(original, output, copyID):
                        changedLibrary = true
                        self?.setState(.saved(original: original, output: output), for: item.id)
                        if let copyID { self?.copyAssetIDs[item.id] = copyID }
                    case let .noReduction(original):
                        self?.setState(.noReduction(original: original), for: item.id)
                    }
                } catch {
                    if Task.isCancelled {
                        self?.setState(.cancelled, for: item.id)
                    } else {
                        self?.setState(.failed(error.localizedDescription), for: item.id)
                    }
                }
                if !Task.isCancelled { self?.phase = .processing(completed: index + 1, total: batch.count) }
            }
            if Task.isCancelled {
                self?.phase = .cancelled
            } else {
                let savedIDs = Set(batch.compactMap { item -> String? in
                    if case .saved = self?.states[item.id] { return item.id }
                    return nil
                })
                if savedIDs.isEmpty {
                    self?.phase = .finished
                } else {
                    self?.phase = .replacing
                    do {
                        let removedIDs = try await replaceOriginals(savedIDs)
                        changedLibrary = changedLibrary || !removedIDs.isEmpty
                        // A committed deletion remains a success even if cancellation arrives afterwards.
                        for id in removedIDs.intersection(savedIDs) {
                            if case let .saved(original, output) = self?.states[id] {
                                self?.setState(.replaced(original: original, output: output), for: id)
                            }
                        }
                        if removedIDs == savedIDs { self?.phase = Task.isCancelled ? .cancelled : .finished }
                        else { self?.phase = .replacementFailure(MediaCompressionError.replacementFailed.localizedDescription) }
                    } catch is CancellationError {
                        self?.phase = .cancelled
                    } catch {
                        self?.phase = .replacementFailure(error.localizedDescription)
                    }
                }
            }
            self?.task = nil
            if changedLibrary { onBatchCompletion() }
        }
        return task
    }
    func cancel() {
        guard isProcessing else { return }
        phase = .cancelling
        task?.cancel()
    }
    deinit { task?.cancel() }
}
