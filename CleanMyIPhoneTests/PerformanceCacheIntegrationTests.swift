//
//  性能缓存集成边界
//
//  覆盖详情页日期缓存失效及选择索引构建取消。
//  通过构建次数和取消结果确认缓存不会复用过期输入。
//  日期缓存用构建次数检查修订号和资源变化；选择索引用已取消任务检查取消传播。
//  输入为合成媒体标识，不需要相册内容。
//

import Foundation
import Testing
@testable import CleanMyIPhone

/// 验证缓存实际接入及构建取消时的行为。
struct PerformanceCacheIntegrationTests {
    /// 检查资源成员或相册修订变化时重建缓存，未变化时复用。
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

    /// 任务已取消时，较大选择索引构建应抛出取消错误。
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
