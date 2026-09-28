import CoreGraphics
import Foundation
import Testing
@testable import ImageFormatConversionKit

@Suite("Video bitrate planning")
struct VideoBitratePlanTests {
    @Test("Original resolution keeps the chosen fraction of the source video bitrate")
    func originalResolutionRate() {
        let source = CGSize(width: 1920, height: 1080)
        let output = VideoBitratePlan.dimensions(source: source, resolution: .original)

        #expect(output.width == 1920)
        #expect(output.height == 1080)
        #expect(VideoBitratePlan.rate(
            sourceRate: 18_000_000,
            fraction: 0.3,
            source: source,
            output: output
        ) == 5_400_000)
    }

    @Test("Lower resolution keeps the aspect ratio and lowers the target bitrate")
    func downscaledRate() {
        let source = CGSize(width: 3840, height: 2160)
        let output = VideoBitratePlan.dimensions(source: source, resolution: .fullHD)

        #expect(output.width == 1920)
        #expect(output.height == 1080)
        #expect(VideoBitratePlan.rate(
            sourceRate: 20_000_000,
            fraction: 0.5,
            source: source,
            output: output
        ) == 2_500_000)
    }

    @Test("Very low source bitrates retain a minimum target")
    func minimumRate() {
        let source = CGSize(width: 1280, height: 720)
        let output = VideoBitratePlan.dimensions(source: source, resolution: .original)

        #expect(VideoBitratePlan.rate(
            sourceRate: 300_000,
            fraction: 0.1,
            source: source,
            output: output
        ) == 250_000)
    }
}
