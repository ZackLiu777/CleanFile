import Foundation
import Testing
@testable import CleanMyIPhone

struct PerformanceCacheIntegrationTests {
    @Test @MainActor func detailDateCacheInvalidation() {
        let store = MediaDateSectionStore()
        var builds = 0
        let first = MediaDatedAsset(id: "a", creationDate: Date(timeIntervalSince1970: 100))
        let second = MediaDatedAsset(id: "b", creationDate: nil)
        let a = store.sections(assetIDs: ["a"], libraryRevision: 1) { builds += 1; return [first] }
        let repeated = store.sections(assetIDs: ["a"], libraryRevision: 1) { builds += 1; return [] }
        #expect(a == repeated)
        #expect(builds == 1)
        let changed = store.sections(assetIDs: ["a", "b"], libraryRevision: 1) { builds += 1; return [first, second] }
        #expect(changed.flatMap(\.assetIDs).count == 2)
        #expect(builds == 2)
        let removed = store.sections(assetIDs: ["a", "b"], libraryRevision: 2) { builds += 1; return [second] }
        #expect(removed.flatMap(\.assetIDs) == ["b"])
        #expect(builds == 3)
    }

    @Test func cancelledIndexBuild() async {
        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try MediaQuickCleanSelectionIndex(categoryAssetIDs: [Set((0..<256).map(String.init))], estimatedByteCountsByID: [:])
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }
}
