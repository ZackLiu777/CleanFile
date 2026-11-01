//
//  媒体滑动审核
//
//  覆盖保留、删除建议、跳过、跳转与撤销。
//  审核只记录本地选择，并验证受保护资源和明确保留不会被批量覆盖。
//  导航到缩略图不产生决策，撤销需要恢复之前的位置与选择。
//  测试使用合成标识和内存会话，不发起 PhotoKit 删除。
//

import Testing
@testable import CleanMyIPhone

/// 验证审核会话的选择、导航、保护项和历史撤销行为。
@Suite("Optional media swipe review")
struct MediaSwipeReviewSessionTests {
    /// 先记录删除与保留，再撤销最后一步，检查位置和先前删除选择保持一致。
    @Test("Swipes only record choices and can be undone")
    func decisionsAndUndo() {
        var session = MediaSwipeReviewSession(assetIDs: ["one", "two"])

        let markedForDeletion = session.decide(.delete)
        #expect(markedForDeletion)
        #expect(session.pendingDeletionIDs == ["one"])
        #expect(session.currentAssetID == "two")
        let kept = session.decide(.keep)
        #expect(kept)
        #expect(session.isComplete)
        #expect(session.keptCount == 1)

        session.undo()
        #expect(session.currentAssetID == "two")
        #expect(session.keptCount == 0)
        #expect(session.pendingDeletionIDs == ["one"])
    }

    /// 建议保留资源受到保护，不可在审核中标记删除。
    @Test("A suggested keeper cannot be marked for deletion")
    func protectsSuggestedKeeper() {
        var session = MediaSwipeReviewSession(
            assetIDs: ["keeper", "other"],
            protectedAssetIDs: ["keeper"]
        )

        let blockedKeeperDeletion = session.decide(.delete)
        #expect(!blockedKeeperDeletion)
        #expect(session.currentAssetID == "keeper")
        #expect(session.pendingDeletionIDs.isEmpty)
        let kept = session.decide(.keep)
        let markedOther = session.decide(.delete)
        #expect(kept)
        #expect(markedOther)
        #expect(session.pendingDeletionIDs == ["other"])
    }

    /// 跳过不可用资源不会将其加入待删除集合。
    @Test("Skipping an unavailable item never adds it to the delete set")
    func skipUnavailable() {
        var session = MediaSwipeReviewSession(assetIDs: ["offline", "visible"])
        session.skip()
        #expect(session.pendingDeletionIDs.isEmpty)
        #expect(session.currentAssetID == "visible")
        session.undo()
        #expect(session.currentAssetID == "offline")
    }

    /// 直接跳到后面的缩略图不会产生决策；完成当前项后仍会回到未审核项。
    @Test("Selecting a thumbnail only navigates; review still visits skipped earlier items")
    func thumbnailNavigation() {
        var session = MediaSwipeReviewSession(assetIDs: ["one", "two", "three"])
        let selected = session.selectAsset(at: 2)
        #expect(selected)
        #expect(session.currentAssetID == "three")
        #expect(session.reviewedCount == 0)
        #expect(!session.isComplete)
        let kept = session.decide(.keep)
        #expect(kept)
        #expect(session.currentAssetID == "one")
        #expect(!session.isComplete)
        session.undo()
        #expect(session.currentAssetID == "three")
        #expect(session.keptCount == 0)
    }

    /// 重新访问资源可覆盖先前决策，撤销后恢复原来的待删除选择。
    @Test("Revisiting a photo can replace its choice and undo restores the prior choice")
    func replaceChoice() {
        var session = MediaSwipeReviewSession(assetIDs: ["one", "two"])
        let firstChoice = session.decide(.delete)
        #expect(firstChoice)
        let selected = session.selectAsset(at: 0)
        #expect(selected)
        let replacement = session.decide(.keep)
        #expect(replacement)
        #expect(session.pendingDeletionIDs.isEmpty)
        session.undo()
        #expect(session.currentAssetID == "one")
        #expect(session.pendingDeletionIDs == ["one"])
    }

    /// 从详情页打开审核时，以指定资源为当前位置且尚无审核记录。
    @Test("Review opened from photo detail starts on that photo")
    func startsFromSelectedPhoto() {
        let session = MediaSwipeReviewSession(
            assetIDs: ["one", "two", "three"],
            initialAssetID: "two"
        )
        #expect(session.currentAssetID == "two")
        #expect(session.currentIndex == 1)
        #expect(session.reviewedCount == 0)
    }

    /// 批量建议排除保护项和明确保留项，并能一次撤销整个批量操作。
    @Test("Bulk similarity selection excludes keepers and preserves explicit keeps; one undo restores all")
    func bulkSuggestedDeletion() {
        var session = MediaSwipeReviewSession(
            assetIDs: ["keeper", "duplicate", "manualKeep", "unrelated"],
            protectedAssetIDs: ["keeper"]
        )
        let navigated = session.selectAsset(at: 2)
        let kept = session.decide(.keep)
        #expect(navigated)
        #expect(kept)
        let count = session.markSuggestedDeletions(["keeper", "duplicate", "manualKeep", "outside"])
        #expect(count == 1)
        #expect(session.pendingDeletionIDs == ["duplicate"])
        #expect(session.keptCount == 1)
        session.undo()
        #expect(session.pendingDeletionIDs.isEmpty)
        #expect(session.decisions["manualKeep"] == .keep)
        #expect(session.currentAssetID == "unrelated")
    }
}
