//
//  验证自定义视频码率规划的尺寸与目标码率计算。
//  覆盖原尺寸、缩小尺寸及低码率下限。
//  测试计划算法，无需编码真实视频。
//  检查目标尺寸保持宽高比，码率按输入及目标分辨率变化并受下限约束。
//  输入是合成视频元数据，不访问相册或编码器。
//

import CoreGraphics
import Foundation
import Testing
@testable import ImageFormatConversionKit

/// 检查分辨率与源码率对输出计划的影响。
@Suite("Video bitrate planning")
struct VideoBitratePlanTests {
    /// 原尺寸保持不变，目标码率等于源码率与所选比例的乘积。
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

    /// 4K 降至 1080p 时检查宽高比及按像素面积调整后的目标码率。
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

    /// 源码率和比例很小时，目标码率不低于计划规定的下限。
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
