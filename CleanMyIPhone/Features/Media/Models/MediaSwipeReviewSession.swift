//
//  滑动审核会话
//
//  记录资源的保留、待删除、跳过与撤销历史，并按未审核项目推进。
//  该会话只维护本地选择，不执行 PhotoKit 删除；受保护资源不能标记删除。
//

import Foundation

/// A review is only a local selection. PhotoKit deletion happens after an explicit final confirmation.
struct MediaSwipeReviewSession {
    /// 审核产生的本地决策：保留或加入待删除集合。
    enum Decision: Equatable {
        case keep
        case delete
    }

    /// 保存一次决策或跳过之前的状态；批量操作的多个步骤作为一组撤销。
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

    /// 按输入顺序去重，并可从指定资源开始；受保护标识不能被选择删除。
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
    /// 跳转到有效索引，越界时保持现状并返回 false。
    mutating func selectAsset(at index: Int) -> Bool {
        guard assetIDs.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    @discardableResult
    /// 记录当前资源的决策并前进；没有当前项或尝试删除受保护项时返回 false。
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

    /// 将当前项标为跳过并前进，保留撤销所需的先前状态。
    mutating func skip() {
        guard let assetID = currentAssetID else { return }
        history.append([Step(assetID: assetID, previousIndex: currentIndex,
                             previousDecision: decisions[assetID], wasSkipped: skippedAssetIDs.contains(assetID))])
        decisions[assetID] = nil
        skippedAssetIDs.insert(assetID)
        advance()
    }

    /// 撤销最近一次单项或批量操作，并恢复该操作之前的当前位置和状态。
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
    /// 只预选会话中未决策且未受保护的候选；一次批量预选可作为整体撤销。
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

    /// 循环查找下一个未决定且未跳过的资源；全部处理后将索引置于末尾。
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
