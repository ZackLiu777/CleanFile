import Testing
@testable import CleanMyIPhone

@Suite("Optional media swipe review")
struct MediaSwipeReviewSessionTests {
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

    @Test("Skipping an unavailable item never adds it to the delete set")
    func skipUnavailable() {
        var session = MediaSwipeReviewSession(assetIDs: ["offline", "visible"])
        session.skip()
        #expect(session.pendingDeletionIDs.isEmpty)
        #expect(session.currentAssetID == "visible")
        session.undo()
        #expect(session.currentAssetID == "offline")
    }

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
