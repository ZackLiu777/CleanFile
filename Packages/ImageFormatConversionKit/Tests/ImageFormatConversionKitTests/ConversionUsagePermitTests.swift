//
//  验证批量使用许可对成功计数和结束回调的限制。
//  模拟负数、超额和重复结束，避免宿主收到多余的成功通知。
//  测试在许可要求的主执行域中运行。
//  一次许可的成功通知不能超过预留数量，结束回调只应交付一次。
//  回调用测试闭包记录，不依赖宿主应用或商店状态。
//

import Testing
@testable import ImageFormatConversionKit

/// 检查成功数量封顶以及结束操作的幂等性。
@Suite("Conversion usage permits")
@MainActor
struct ConversionUsagePermitTests {
    /// 模拟重复及超额回调，验证成功计数封顶且结束仅通知一次。
    @Test("Duplicate completion callbacks cannot overcharge a reservation")
    func clampedAndIdempotent() {
        var delivered = 0
        var finished = 0
        let permit = ConversionUsagePermit(count: 3, onSuccess: { delivered += $0 }, onFinish: { finished += 1 })
        permit.recordSuccess(-1)
        permit.recordSuccess(2)
        permit.recordSuccess(100)
        permit.finish()
        permit.finish()
        permit.recordSuccess()
        #expect(delivered == 3)
        #expect(permit.successfulCount == 3)
        #expect(finished == 1)
    }
}
