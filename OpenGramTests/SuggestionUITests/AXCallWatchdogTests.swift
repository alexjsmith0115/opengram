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

    @Test("shouldSkip returns true while a different call is in flight (busy guard)")
    func busyGuardSkipsWhileCallInFlight() {
        let watchdog = AXCallWatchdog(hangThreshold: 0.8, blocklistDuration: 30.0)
        watchdog.beginCall(bundleID: "com.test.busy", attribute: kAXBoundsForRangeParameterizedAttribute)
        // Another bundle ID should be skipped while a call is in flight (< 1.2s)
        #expect(watchdog.shouldSkip(for: "com.other.app") == true)
        watchdog.endCall()
    }
}
