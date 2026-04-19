import Testing
import Foundation
@preconcurrency import ApplicationServices

@testable import OpenGramLib

@Suite("AXCallWatchdog")
struct AXCallWatchdogTests {

    @Test("shouldSkip returns false for unknown bundle ID with no active calls")
    func shouldSkipReturnsFalseForUnknownBundle() {
        let watchdog = AXCallWatchdog(hangThreshold: 0.05, blocklistDuration: 0.1)
        #expect(watchdog.shouldSkip(for: "com.unknown.app") == false)
    }

    @Test("shouldSkip returns true for bundle ID added to blocklist after timeout")
    func shouldSkipReturnsTrueAfterTimeout() async throws {
        let watchdog = AXCallWatchdog(hangThreshold: 0.05, blocklistDuration: 0.5)
        watchdog.beginCall(bundleID: "com.test.hang", attribute: kAXBoundsForRangeParameterizedAttribute)
        // Sleep past hangThreshold (0.05s) so the timer fires and blocklists the app
        try await Task.sleep(for: .milliseconds(150))
        #expect(watchdog.shouldSkip(for: "com.test.hang") == true)
    }

    @Test("blocklist entry expires after blocklistDuration and shouldSkip returns false")
    func blocklistExpiresAfterDuration() async throws {
        let watchdog = AXCallWatchdog(hangThreshold: 0.05, blocklistDuration: 0.1)
        watchdog.beginCall(bundleID: "com.test.expire", attribute: kAXBoundsForRangeParameterizedAttribute)
        // Wait for hang threshold to trigger blocklist
        try await Task.sleep(for: .milliseconds(150))
        // Should be blocklisted now
        #expect(watchdog.shouldSkip(for: "com.test.expire") == true)
        // Wait for blocklist to expire (blocklistDuration = 0.1s)
        try await Task.sleep(for: .milliseconds(200))
        #expect(watchdog.shouldSkip(for: "com.test.expire") == false)
    }

    @Test("beginCall + endCall clears active state, no blocklist entry added")
    func endCallClearsActiveState() async throws {
        let watchdog = AXCallWatchdog(hangThreshold: 0.05, blocklistDuration: 0.5)
        watchdog.beginCall(bundleID: "com.test.clean", attribute: kAXBoundsForRangeParameterizedAttribute)
        watchdog.endCall()
        // Sleep past hangThreshold — timer should NOT blocklist since call ended
        try await Task.sleep(for: .milliseconds(150))
        #expect(watchdog.shouldSkip(for: "com.test.clean") == false)
    }

    @Test("shouldSkip returns false for non-blocklisted bundle during in-flight call (busy guard removed)")
    func shouldSkipReturnsFalseDuringInFlightCall() {
        let watchdog = AXCallWatchdog(hangThreshold: 0.8, blocklistDuration: 30.0)
        watchdog.beginCall(bundleID: "com.test.busy", attribute: kAXBoundsForRangeParameterizedAttribute)
        // A different bundle must NOT be skipped while a call is in flight — serialization is now the queue's job.
        #expect(watchdog.shouldSkip(for: "com.other.app") == false)
        // The bundle currently making the call must also not be skipped (no self-busy-guard).
        #expect(watchdog.shouldSkip(for: "com.test.busy") == false)
        watchdog.endCall()
    }
}
