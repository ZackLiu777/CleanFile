// 启动状态及高级功能入口的状态转换测试。
//
// 启动动画与权益检查可能以不同顺序完成；这些用例记录两者的协调方式、
// 失败后的恢复路径，以及进入内容后不重复覆盖界面的约束。
// 同时验证媒体哈希缓存的编码往返和版本兼容性。

import Foundation
import Testing
@testable import CleanMyIPhone

/// 覆盖启动动画、目的地检查和缓存兼容性的主要状态转换。
struct AppLaunchStateTests {
    /// 权益检查先完成时，内容仍须等待开场动画结束。
    @Test("A ready destination does not skip the opening animation")
    func fastVerificationPreservesAnimation() {
        var state = AppLaunchState(destination: .preparing)
        state.destinationChanged(to: .ready)
        #expect(state.phase == .animating)
        #expect(state.showsOpening)
        state.animationFinished()
        #expect(state.phase == .content)
        #expect(!state.showsOpening)
    }

    /// 动画先结束时继续等待目的地，避免过早进入内容。
    @Test("Slow verification retains the same opening until a destination is available")
    func slowVerificationKeepsOpening() {
        var state = AppLaunchState(destination: .preparing)
        state.animationFinished()
        #expect(state.phase == .waitingForDestination)
        #expect(state.showsOpening)
        state.destinationChanged(to: .ready)
        #expect(state.phase == .content)
    }

    /// 检查失败可进入恢复界面，并在重新检查成功后继续进入内容。
    @Test("Verification failure exposes recovery after the animation and can recover")
    func verificationFailureIsRecoverable() {
        var state = AppLaunchState(destination: .preparing)
        state.destinationChanged(to: .recovery)
        #expect(state.phase == .animating)
        state.animationFinished()
        #expect(state.phase == .recovery)
        #expect(!state.showsOpening)
        state.destinationChanged(to: .preparing)
        #expect(!state.showsOpening)
        state.destinationChanged(to: .ready)
        #expect(state.phase == .content)
    }

    /// 首次进入内容后，前台刷新和重复回调不应重新显示开场。
    @Test("Foreground checks and repeated completion never replay the opening")
    func foregroundRefreshDoesNotCoverContent() {
        var state = AppLaunchState(destination: .ready)
        state.animationFinished()
        state.destinationChanged(to: .preparing)
        state.animationFinished()
        state.destinationChanged(to: .recovery)
        #expect(state.phase == .content)
    }

    /// 序列化保留完整哈希及源文件版本；不兼容的缓存版本不得复用。
    @Test("Hash cache round trips without losing source version or hash precision")
    func hashCacheRoundTrip() throws {
        let key = FeatureCacheKey(
            modificationDate: Date(timeIntervalSinceReferenceDate: 42),
            pixelWidth: 4032, pixelHeight: 3024
        )
        let original = MediaHashCacheSnapshot(
            version: MediaHashCacheSnapshot.currentVersion,
            entries: ["asset": .init(cacheKey: key, hash: UInt64.max)]
        )
        let restored = try JSONDecoder().decode(
            MediaHashCacheSnapshot.self, from: JSONEncoder().encode(original)
        )
        #expect(restored.compatibleEntries["asset"]?.hash == UInt64.max)
        #expect(restored.compatibleEntries["asset"]?.cacheKey == key)
        let editedKey = FeatureCacheKey(
            modificationDate: Date(timeIntervalSinceReferenceDate: 43),
            pixelWidth: 4032, pixelHeight: 3024
        )
        #expect(restored.compatibleEntries["asset"]?.cacheKey != editedKey)
        let incompatible = MediaHashCacheSnapshot(version: -1, entries: restored.entries)
        #expect(incompatible.compatibleEntries.isEmpty)
    }
}

/// 验证高级功能入口在启动阶段与根视图生命周期内的展示时机。
@MainActor
struct PremiumEntryPresentationTests {
    /// 启动尚未完成时不消耗展示机会，完成后同一机会只能使用一次。
    @Test("An early entitlement result waits for the opening transition without consuming the offer")
    func waitsForOpening() {
        var state = PremiumEntryPresentation()
        let early = state.consumePresentation(for: .notEntitled, openingCompleted: false)
        #expect(!early)
        let ready = state.consumePresentation(for: .notEntitled, openingCompleted: true)
        #expect(ready)
        let repeated = state.consumePresentation(for: .notEntitled, openingCompleted: true)
        #expect(!repeated)
    }

    /// 未订阅用户在同一根视图生命周期内最多收到一次入口提示。
    @Test("Free users see only one offer for the root lifetime")
    func freeUserVisits() {
        var state = PremiumEntryPresentation()
        let presents1 = state.consumePresentation(for: .checking)
        #expect(!presents1)
        let presents2 = state.consumePresentation(for: .notEntitled)
        #expect(presents2)
        let presents3 = state.consumePresentation(for: .notEntitled)
        #expect(!presents3)
        let presents4 = state.consumePresentation(for: .notEntitled)
        #expect(!presents4)
    }

    /// 已订阅或仍在检查权益时不展示购买提示。
    @Test("Premium and unresolved access do not trigger an offer")
    func premiumVisits() {
        var state = PremiumEntryPresentation()
        let presents5 = state.consumePresentation(for: .entitled)
        #expect(!presents5)
        let presents6 = state.consumePresentation(for: .checking)
        #expect(!presents6)
        let presents7 = state.consumePresentation(for: .entitled)
        #expect(!presents7)
    }
}
