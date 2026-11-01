//
//  验证照片原件替换的媒体类型约束和对应指南文案。
//  音频候选必须在进入 PhotoKit 变更前被拒绝。
//  测试不以真实照片资源作为替换素材。
//  仅图片和视频具备候选资格，指南应说明音频不参与原件替换。
//  直接验证模型与文案，无需更改照片图库。
//

import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 检查不支持的音频替换不会进入照片图库变更。
@Suite("Original replacement contracts")
struct ConversionReplacementTests {
    /// 原件替换只支持照片图库中的图片和视频，音频不能列入候选。
    @Test("Only Photos images and videos are eligible for replacement")
    func supportedReplacementKindsExcludeAudio() {
        #expect(ConversionOriginalReplacementService.supportedKinds == [.image, .video])
        #expect(!ConversionOriginalReplacementService.supportedKinds.contains(.audio))
    }

    /// 检查音频候选在 PhotoKit 变更开始前被拒绝。
    @Test("Audio replacement is rejected before PhotoKit changes begin")
    func audioReplacementIsRejected() async {
        let candidate = ConversionReplacementCandidate(
            id: UUID(),
            outputURL: URL(fileURLWithPath: "/tmp/compressed-audio.mp3"),
            photoAssetIdentifier: "audio-has-no-photo-asset",
            kind: .audio,
            sourceBytes: 1_000,
            outputBytes: 500
        )

        do {
            _ = try await ConversionOriginalReplacementService.replace([candidate])
            Issue.record("Audio replacement unexpectedly succeeded")
        } catch ConversionOriginalReplacementError.unsupportedOutput {
            // Expected: audio originals cannot be safely deleted through PhotoKit.
        } catch {
            Issue.record("Unexpected replacement error: \(error)")
        }
    }

    /// 音频替换限制的标题和详细说明必须有本地化内容，而非回退为键名。
    @Test("The guide explains the audio replacement limitation")
    func audioReplacementGuideCopyExists() {
        let title = L10n.string("conversion.guide.audio_replace.title")
        let detail = L10n.string("conversion.guide.audio_replace.detail")

        #expect(title != "conversion.guide.audio_replace.title")
        #expect(detail != "conversion.guide.audio_replace.detail")
        #expect(!title.isEmpty)
        #expect(detail.count > 40)
    }
}
