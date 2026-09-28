import Foundation

/// A review is only a local selection. PhotoKit deletion happens after an explicit final confirmation.
struct MediaSwipeReviewSession {
    enum Decision: Equatable {
        case keep
        case delete
    }

    private struct Step {
        let assetID: String
        let previousIndex: Int
        let previousDecision: Decision?
        let wasSkipped: Bool
    }

    let assetIDs: [String]
    let protectedAssetIDs: Set<String>
    private(set) var currentIndex = 0
    private(set) var decisions: [String: Decision] = [:]
    private(set) var skippedAssetIDs: Set<String> = []
    private var history: [[Step]] = []

    init(assetIDs: [String], protectedAssetIDs: Set<String> = [], initialAssetID: String? = nil) {
        var seen = Set<String>()
        self.assetIDs = assetIDs.filter { seen.insert($0).inserted }
        self.protectedAssetIDs = protectedAssetIDs
        if let initialAssetID, let index = self.assetIDs.firstIndex(of: initialAssetID) {
            currentIndex = index
        }
    }

    var currentAssetID: String? {
        assetIDs.indices.contains(currentIndex) ? assetIDs[currentIndex] : nil
    }

    var isComplete: Bool {
        assetIDs.allSatisfy { decisions[$0] != nil || skippedAssetIDs.contains($0) }
    }
    var canUndo: Bool { !history.isEmpty }
    var hasDecisions: Bool { !decisions.isEmpty }
    var pendingDeletionIDs: Set<String> {
        Set(decisions.compactMap { $0.value == .delete ? $0.key : nil })
    }
    var keptCount: Int { decisions.values.count { $0 == .keep } }

    var reviewedCount: Int { decisions.count + skippedAssetIDs.count }

    @discardableResult
    mutating func selectAsset(at index: Int) -> Bool {
        guard assetIDs.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    @discardableResult
    mutating func decide(_ decision: Decision) -> Bool {
        guard let assetID = currentAssetID else { return false }
        guard decision != .delete || !protectedAssetIDs.contains(assetID) else { return false }
        history.append([Step(assetID: assetID, previousIndex: currentIndex,
                             previousDecision: decisions[assetID], wasSkipped: skippedAssetIDs.contains(assetID))])
        decisions[assetID] = decision
        skippedAssetIDs.remove(assetID)
        advance()
        return true
    }

    mutating func skip() {
        guard let assetID = currentAssetID else { return }
        history.append([Step(assetID: assetID, previousIndex: currentIndex,
                             previousDecision: decisions[assetID], wasSkipped: skippedAssetIDs.contains(assetID))])
        decisions[assetID] = nil
        skippedAssetIDs.insert(assetID)
        advance()
    }

    mutating func undo() {
        guard let steps = history.popLast(), let previousIndex = steps.first?.previousIndex else { return }
        currentIndex = previousIndex
        for step in steps {
            decisions[step.assetID] = step.previousDecision
            if step.wasSkipped { skippedAssetIDs.insert(step.assetID) }
            else { skippedAssetIDs.remove(step.assetID) }
        }
    }

    /// Only candidates in this review may be preselected. Explicit keeps always win.
    @discardableResult
    mutating func markSuggestedDeletions(_ candidateIDs: Set<String>) -> Int {
        let eligibleIDs = assetIDs.filter {
            candidateIDs.contains($0)
                && !protectedAssetIDs.contains($0)
                && decisions[$0] == nil
        }
        guard !eligibleIDs.isEmpty else { return 0 }
        history.append(eligibleIDs.map {
            Step(assetID: $0, previousIndex: currentIndex,
                 previousDecision: decisions[$0], wasSkipped: skippedAssetIDs.contains($0))
        })
        for identifier in eligibleIDs {
            decisions[identifier] = .delete
            skippedAssetIDs.remove(identifier)
        }
        return eligibleIDs.count
    }

    private mutating func advance() {
        guard !assetIDs.isEmpty else { return }
        for offset in 1...assetIDs.count {
            let index = (currentIndex + offset) % assetIDs.count
            let identifier = assetIDs[index]
            if decisions[identifier] == nil && !skippedAssetIDs.contains(identifier) {
                currentIndex = index
                return
            }
        }
        currentIndex = assetIDs.count
    }
}
