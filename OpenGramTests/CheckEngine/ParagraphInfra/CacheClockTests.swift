import Testing
import Foundation
@testable import OpenGramLib

/// Test-local fake. Not published in the main module — cache tests will declare their own
/// or reuse this pattern. D-14, D-19.
final class FakeClock: CacheClock, @unchecked Sendable {
    var current: Date
    init(_ seed: Date) { self.current = seed }
    func now() -> Date { current }
}

@Suite struct CacheClockTests {

    @Test func systemClockReturnsTimeCloseToWallClock() {
        let before = Date()
        let clockNow = SystemClock().now()
        let after = Date()
        #expect(clockNow >= before.addingTimeInterval(-0.001))
        #expect(clockNow <= after.addingTimeInterval(0.001))
    }

    @Test func fakeClockReturnsSeedValue() {
        let seed = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FakeClock(seed)
        #expect(clock.now() == seed)
    }

    @Test func fakeClockAdvancesDeterministically() {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        clock.current = Date(timeIntervalSince1970: 1800)
        #expect(clock.now().timeIntervalSince1970 == 1800)
    }
}
