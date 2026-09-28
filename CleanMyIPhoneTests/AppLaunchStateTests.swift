import Foundation
import Testing
@testable import CleanMyIPhone

struct AppLaunchStateTests {
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

    @Test("Slow verification retains the same opening until a destination is available")
    func slowVerificationKeepsOpening() {
        var state = AppLaunchState(destination: .preparing)
        state.animationFinished()
        #expect(state.phase == .waitingForDestination)
        #expect(state.showsOpening)
        state.destinationChanged(to: .ready)
        #expect(state.phase == .content)
    }

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

    @Test("Foreground checks and repeated completion never replay the opening")
    func foregroundRefreshDoesNotCoverContent() {
        var state = AppLaunchState(destination: .ready)
        state.animationFinished()
        state.destinationChanged(to: .preparing)
        state.animationFinished()
        state.destinationChanged(to: .recovery)
        #expect(state.phase == .content)
    }

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
