import Testing
@testable import ImageFormatConversionKit

@Suite("Conversion usage permits")
@MainActor
struct ConversionUsagePermitTests {
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
