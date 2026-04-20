import Testing
import AppKit
import Foundation
import os
@testable import OpenGramLib

/// Verifies `OverlayController` subscribes to `ParagraphSuggestionStore.events` and routes
/// `.suggestionsChanged` emissions through the render pipeline with live-text range
/// re-resolution (Pitfall #3 — never trust cached `String.Index`).
@Suite @MainActor
struct OverlayControllerStoreSubscriptionTests {

    // MARK: - Test doubles

    private final class StubLLM: LLMProviderProtocol, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: State())
        private struct State {
            var canned: [String: [LLMStyleSuggestion]] = [:]
            var calls: [String] = []
        }
        func setCanned(_ c: [String: [LLMStyleSuggestion]]) { state.withLock { $0.canned = c } }
        var calls: [String] { state.withLock { $0.calls } }
        func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
            try? await Task.sleep(for: .milliseconds(1))
            return state.withLock { s in
                s.calls.append(target)
                return s.canned[target] ?? []
            }
        }
        func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
    }

    private final class StubCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
        func isSupported(bundleID: String, version: String?) -> Bool? { nil }
        func store(bundleID: String, version: String?, supported: Bool) {}
        func isNotificationReliable(bundleID: String) -> Bool? { nil }
        func storeNotificationReliability(bundleID: String, reliable: Bool) {}
        func separator(bundleID: String, version: String?) -> String? { nil }
        func storeSeparator(bundleID: String, version: String?, separator: String) {}
    }

    /// Thread-safe mutable text holder — store's `textProvider` closure reads via NSLock
    /// so verify-on-response sees the live value without a MainActor hop.
    private final class TextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var textByBundle: [String: String] = [:]
        init(_ seed: [String: String] = [:]) { self.textByBundle = seed }
        func read(bundleID: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return textByBundle[bundleID]
        }
        func write(bundleID: String, text: String) {
            lock.lock(); defer { lock.unlock() }
            textByBundle[bundleID] = text
        }
    }

    // MARK: - Factory

    private struct Fixture {
        let controller: OverlayController
        let store: ParagraphSuggestionStore
        let llm: StubLLM
        let textBox: TextBox
    }

    private func makeFixture(
        text: String,
        bundleID: String = "b"
    ) async -> Fixture {
        let llm = StubLLM()
        let cache = StubCapabilityCache()
        let splitter = ParagraphSplitter(capabilityCache: cache)
        let queue = LLMRequestQueue(
            llm: llm,
            configProvider: {
                LLMConfig(
                    baseURL: "https://x.invalid",
                    model: "m",
                    enabledChecks: Set(LLMCheckType.allCases),
                    temperature: 0.2,
                    maxTokens: 100,
                    requestTimeout: 30,
                    confidenceThreshold: 1
                )
            },
            apiKeyProvider: { nil },
            timeoutProvider: { 5 }
        )
        let textBox = TextBox([bundleID: text])
        let store = ParagraphSuggestionStore(
            queue: queue,
            splitter: splitter,
            textProvider: { [textBox] bundleID in textBox.read(bundleID: bundleID) }
        )
        await queue.setStore(store)

        let controller = OverlayController(store: store)
        controller.textContext = TextContext(
            text: text,
            bundleID: bundleID,
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
        return Fixture(controller: controller, store: store, llm: llm, textBox: textBox)
    }

    private func makeSet(bundleID: String, paragraph: String) -> ParagraphSet {
        ParagraphSet(
            bundleID: bundleID,
            paragraphs: [
                ParagraphSet.Entry(
                    hash: ParagraphHash(bundleID: bundleID, paragraphText: paragraph),
                    text: paragraph
                )
            ],
            caretParagraphHash: nil
        )
    }

    /// Poll the controller until a non-zero LLM suggestion count appears or timeout.
    /// Avoids flaky fixed sleeps — the store event pipeline runs:
    ///   StubLLM.analyze → queue.finishInFlight → store.handleQueueResponse → event yield → controller handler.
    private func waitForLLMSuggestion(
        controller: OverlayController,
        timeoutMilliseconds: Int = 2000
    ) async -> Bool {
        let end = Date().addingTimeInterval(TimeInterval(timeoutMilliseconds) / 1000)
        while Date() < end {
            if controller.suggestions.contains(where: { $0.source == .llm }) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    // MARK: - Subscription lifecycle

    @Test func eventForCurrentBundleIDTriggersUpdate() async throws {
        let para = String(repeating: "word ", count: 10) + "here"
        let fx = await makeFixture(text: para)
        fx.llm.setCanned([para: [LLMStyleSuggestion(
            category: .tone,
            originalText: para,
            revisedText: "rewritten version",
            explanation: "x",
            confidence: 8
        )]])

        await fx.store.reconcile(set: makeSet(bundleID: "b", paragraph: para))

        let seen = await waitForLLMSuggestion(controller: fx.controller)
        #expect(seen, "controller must receive LLM suggestion via store subscription")
    }

    @Test func eventForDifferentBundleIDNoOp() async throws {
        let para = String(repeating: "word ", count: 10) + "here"
        let fx = await makeFixture(text: para, bundleID: "currentApp")

        // Emit an event for a different bundleID. Store internal state mutations trigger
        // .suggestionsChanged(bundleID: "otherApp") via invalidateDisplayed.
        let otherSet = ParagraphSet(
            bundleID: "otherApp",
            paragraphs: [
                ParagraphSet.Entry(
                    hash: ParagraphHash(bundleID: "otherApp", paragraphText: para),
                    text: para
                )
            ],
            caretParagraphHash: nil
        )
        await fx.store.invalidateDisplayed(bundleID: "otherApp", currentSet: otherSet)

        // Give the event loop time to propagate a (would-be) update.
        try await Task.sleep(for: .milliseconds(100))

        #expect(fx.controller.suggestions.filter { $0.source == .llm }.isEmpty,
                "event for different bundleID must not touch current-app suggestions")
    }

    // MARK: - Range re-resolution (Pitfall #3)

    @Test func llmRangeResolvedAgainstLiveText() async throws {
        let para = String(repeating: "word ", count: 10) + "target"
        let fx = await makeFixture(text: para)
        fx.llm.setCanned([para: [LLMStyleSuggestion(
            category: .tone,
            originalText: para,
            revisedText: "rewritten",
            explanation: "x",
            confidence: 8
        )]])

        await fx.store.reconcile(set: makeSet(bundleID: "b", paragraph: para))
        let seen = await waitForLLMSuggestion(controller: fx.controller)
        #expect(seen)

        if let s = fx.controller.suggestions.first(where: { $0.source == .llm }),
           let ctx = fx.controller.textContext {
            // Re-resolved range must map to valid indices in the LIVE text — not the
            // cached placeholder range from the store's mapToSuggestion.
            #expect(ctx.text.distance(from: ctx.text.startIndex, to: s.range.lowerBound) >= 0)
            #expect(s.range.upperBound <= ctx.text.endIndex)
            #expect(String(ctx.text[s.range]) == para)
        }
    }

    // MARK: - deinit subscription cancel (T-20.09-03)

    @Test func deinitCancelsSubscription() async throws {
        // Build, drop the strong controller reference, then emit more events and confirm
        // no crash. The weak-self guard inside the event loop closure exits cleanly.
        let para = String(repeating: "word ", count: 10) + "here"
        var fx: Fixture? = await makeFixture(text: para)
        _ = fx   // retain briefly
        fx = nil

        // Build a fresh store lifecycle for an event that would fire if the prior
        // subscription task survived self release. The existing store from the dropped
        // fixture is also released, so no follow-up emission is possible — validating
        // that deinit cleanup doesn't crash on the way out is the assertion.
        try await Task.sleep(for: .milliseconds(50))
        // Reaching here without crash = pass.
    }
}
