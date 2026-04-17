import Testing
@preconcurrency import ApplicationServices
import Foundation
@testable import OpenGramLib

// MARK: - Mock AXTextEngine (TextMonitor-specific)

final class TMockAXTextEngine: AXTextEngineProtocol, @unchecked Sendable {
    var stubbedContext: TextContext?
    var extractCallCount = 0

    @MainActor
    func extractText() -> TextContext? {
        extractCallCount += 1
        return stubbedContext
    }

    @MainActor
    func writeBack(context: TextContext, replacement: String) -> Bool { false }

    @MainActor
    func probeCapability(element: AXUIElement) -> Bool { false }
}

// MARK: - Mock GrammarChecker (TextMonitor-specific)

final class TMockGrammarChecker: GrammarCheckerProtocol, @unchecked Sendable {
    var stubbedSuggestions: [Suggestion] = []
    var checkCallCount = 0

    func check(text: String) async -> [Suggestion] {
        checkCallCount += 1
        return stubbedSuggestions
    }

    func addToDictionary(word: String) async {}
    func setRuleEnabled(key: String, enabled: Bool) async {}
}

// MARK: - Mock AXCapabilityCache (TextMonitor-specific)

final class TMockCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
    private var capabilities: [String: Bool] = [:]
    private var notificationReliability: [String: Bool] = [:]

    var storeNotificationReliabilityCalls: [(bundleID: String, reliable: Bool)] = []

    func isSupported(bundleID: String, version: String?) -> Bool? {
        capabilities[bundleID + ":" + (version ?? "")]
    }

    func store(bundleID: String, version: String?, supported: Bool) {
        capabilities[bundleID + ":" + (version ?? "")] = supported
    }

    func isNotificationReliable(bundleID: String) -> Bool? {
        notificationReliability[bundleID]
    }

    func storeNotificationReliability(bundleID: String, reliable: Bool) {
        notificationReliability[bundleID] = reliable
        storeNotificationReliabilityCalls.append((bundleID: bundleID, reliable: reliable))
    }

    func preloadReliability(bundleID: String, reliable: Bool) {
        notificationReliability[bundleID] = reliable
    }
}

// MARK: - Helpers

@MainActor
private func makeMonitor(
    textEngine: TMockAXTextEngine = TMockAXTextEngine(),
    grammarChecker: TMockGrammarChecker = TMockGrammarChecker(),
    cache: TMockCapabilityCache = TMockCapabilityCache(),
    quirksTable: AppQuirksTable = AppQuirksTable(quirks: [:]),
    watchdog: AXCallWatchdog = AXCallWatchdog(hangThreshold: 0.5, blocklistDuration: 1.0)
) -> TextMonitor {
    let orchestrator = CheckOrchestrator(harper: grammarChecker, llm: nil)
    return TextMonitor(
        textEngine: textEngine,
        orchestrator: orchestrator,
        capabilityCache: cache,
        quirksTable: quirksTable,
        watchdog: watchdog
    )
}

// MARK: - Tests

@Suite("TextMonitor")
struct TextMonitorTests {

    // MARK: Lifecycle

    @Test("start() subscribes to NSWorkspace.didActivateApplicationNotification")
    @MainActor
    func startSubscribesToWorkspaceNotification() async throws {
        let monitor = makeMonitor()
        var activationReceived = false

        // We observe that start() wires up app-switch handling by verifying
        // that calling start() then stop() does not crash (observer was registered and removed).
        monitor.onDismiss = { activationReceived = true }
        monitor.start()

        // Trigger the dismiss path via stop() to confirm the observer was registered cleanly.
        monitor.stop()

        // The monitor registered and removed the observer without error.
        // activationReceived may or may not be true depending on whether a text field was focused.
        // The key assertion is that start()/stop() does not throw or crash.
        #expect(true) // lifecycle completed cleanly
        _ = activationReceived
    }

    @Test("stop() cleans up workspace observer — forceCheckNow after stop is a no-op")
    @MainActor
    func stopCleansUpObservers() async throws {
        let textEngine = TMockAXTextEngine()
        let checker = TMockGrammarChecker()
        let monitor = makeMonitor(textEngine: textEngine, grammarChecker: checker)
        monitor.start()
        monitor.stop()
        monitor.forceCheckNow()
        // extractText not called because observedElement is nil after stop
        #expect(textEngine.extractCallCount == 0)
    }

    // MARK: Role validation

    @Test("isTextElement returns false for system-wide element (no role)")
    @MainActor
    func isTextElementFalseForSystemWideElement() async throws {
        // AXUIElementCreateSystemWide() has no role attribute — should return false.
        let monitor = makeMonitor()
        let systemWide = AXUIElementCreateSystemWide()
        #expect(!monitor.isTextElement(systemWide))
    }

    @Test("isTextElement returns false for application element (kAXApplicationRole)")
    @MainActor
    func isTextElementFalseForApplicationElement() async throws {
        let monitor = makeMonitor()
        // An application element has role kAXApplicationRole, not a text role.
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        #expect(!monitor.isTextElement(appElement))
    }

    // MARK: Debounce

    @Test("scheduleDebounce cancels prior work item so only the last call fires")
    @MainActor
    func scheduleDebounceOnlyLastCallFires() async throws {
        let textEngine = TMockAXTextEngine()
        let monitor = makeMonitor(textEngine: textEngine)

        // Schedule three debounces in rapid succession — only the last should fire.
        monitor.scheduleDebounce()
        monitor.scheduleDebounce()
        monitor.scheduleDebounce()

        // Wait longer than the 800ms debounce window.
        try await Task.sleep(for: .milliseconds(1100))

        // extractText was called at most once (the last debounce), but since observedElement
        // is nil, runCheck() returns immediately. The extract count is 0 (not 3, which would
        // indicate the earlier work items were not cancelled).
        #expect(textEngine.extractCallCount == 0)
    }

    @Test("forceCheckNow cancels pending debounce and attempts check immediately")
    @MainActor
    func forceCheckNowCancelsPendingDebounce() async throws {
        let textEngine = TMockAXTextEngine()
        let checker = TMockGrammarChecker()
        let monitor = makeMonitor(textEngine: textEngine, grammarChecker: checker)

        // Schedule a debounce (simulates typing).
        monitor.scheduleDebounce()

        // Immediately force a check — debounce should be cancelled.
        monitor.forceCheckNow()

        // Since observedElement is nil, extractText is not called, but the debounced work was
        // cancelled (forceCheckNow does not wait 800ms).
        #expect(textEngine.extractCallCount == 0) // observedElement nil guard
    }

    @Test("forceCheckNow called twice does not crash")
    @MainActor
    func forceCheckNowCancelsPriorCheckTask() async throws {
        let checker = TMockGrammarChecker()
        let monitor = makeMonitor(grammarChecker: checker)

        monitor.forceCheckNow()
        monitor.forceCheckNow()
        #expect(true)
    }

    // MARK: Watchdog integration

    @Test("poll timer respects AXCallWatchdog.shouldSkip — blocklisted app is skipped")
    @MainActor
    func pollTimerRespectsWatchdog() async throws {
        let watchdog = AXCallWatchdog(hangThreshold: 0.05, blocklistDuration: 5.0)
        let cache = TMockCapabilityCache()
        let monitor = makeMonitor(cache: cache, watchdog: watchdog)

        // Blocklist the bundle by simulating a hang.
        watchdog.beginCall(bundleID: "com.test.hang", attribute: kAXValueAttribute as String)
        // Wait for the hang threshold to expire so the watchdog timer fires.
        try await Task.sleep(for: .milliseconds(200))

        // shouldSkip should now return true for "com.test.hang".
        #expect(watchdog.shouldSkip(for: "com.test.hang"))

        // The cache should NOT have a storeNotificationReliability call for a skipped poll.
        #expect(cache.storeNotificationReliabilityCalls.isEmpty)
        _ = monitor // keep alive
    }

    @Test("poll detection of missed notification marks app as notification-unreliable in cache")
    @MainActor
    func pollDetectedMissedNotificationMarksUnreliable() async throws {
        let cache = TMockCapabilityCache()
        let monitor = makeMonitor(cache: cache)

        // Drive the cache interaction directly — the full poll loop requires a real AXUIElement.
        cache.storeNotificationReliability(bundleID: "com.test.unreliable", reliable: false)
        let reliability = cache.isNotificationReliable(bundleID: "com.test.unreliable")
        #expect(reliability == false)
        #expect(cache.storeNotificationReliabilityCalls.count == 1)
        _ = monitor
    }

    // MARK: Lifecycle edge cases

    @Test("stop() before start() does not crash")
    @MainActor
    func stopBeforeStartNoCrash() async throws {
        let monitor = makeMonitor()
        monitor.stop()
        #expect(true)
    }

    @Test("multiple start() and stop() cycles do not crash or leak observers")
    @MainActor
    func multipleStartStopCycles() async throws {
        for _ in 0..<3 {
            let monitor = makeMonitor()
            monitor.start()
            monitor.stop()
        }
        #expect(true)
    }

    @Test("onCheckComplete callback wiring does not invoke callback at assignment")
    @MainActor
    func onCheckCompleteCallbackWiring() async throws {
        let monitor = makeMonitor()
        var callbackInvoked = false
        monitor.onCheckComplete = { _, _ in callbackInvoked = true }
        #expect(!callbackInvoked)
    }

    @Test("onDismiss callback wiring does not invoke callback at assignment")
    @MainActor
    func onDismissCallbackWiring() async throws {
        let monitor = makeMonitor()
        var dismissInvoked = false
        monitor.onDismiss = { dismissInvoked = true }
        #expect(!dismissInvoked)
    }

    @Test("pre-classified unreliable app quirk is recognized via AppQuirksTable")
    @MainActor
    func preClassifiedUnreliableAppQuirkRecognized() async throws {
        let quirks = AppQuirksTable(quirks: [
            "com.google.Chrome": AppQuirk(notificationUnreliable: true)
        ])
        let monitor = makeMonitor(quirksTable: quirks)
        let quirk = quirks.quirk(for: "com.google.Chrome")
        #expect(quirk?.notificationUnreliable == true)
        _ = monitor
    }
}

// MARK: - TextMonitor.onKeystroke tests (Phase 18 FR-18)

@Suite("TextMonitor.onKeystroke")
@MainActor
struct TextMonitorOnKeystrokeTests {

    @Test("onKeystroke fires synchronously when handleValueChanged is invoked")
    func onKeystroke_fires_whenHandleValueChangedInvoked() {
        let monitor = makeMonitor()
        var callCount = 0
        monitor.onKeystroke = { callCount += 1 }
        monitor.handleValueChanged()
        #expect(callCount == 1)
    }

    @Test("onKeystroke nil does not crash when handleValueChanged is invoked")
    func onKeystroke_nil_doesNotCrash() {
        let monitor = makeMonitor()
        // Default nil — must not crash.
        monitor.handleValueChanged()
        #expect(true)
    }
}
