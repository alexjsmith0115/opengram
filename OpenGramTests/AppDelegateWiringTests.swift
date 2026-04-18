import Testing
import AppKit
@preconcurrency import ApplicationServices

@testable import OpenGramLib

// MARK: - MockGrammarChecker

final class MockGrammarChecker: GrammarCheckerProtocol, @unchecked Sendable {
    var addedWords: [String] = []
    var checkResult: [Suggestion] = []

    func check(text: String) async -> [Suggestion] { checkResult }
    func addToDictionary(word: String) async { addedWords.append(word) }
    func setRuleEnabled(key: String, enabled: Bool) async {}
}

// MARK: - Helpers

private func makeWiringSuggestion(id: UUID = UUID(), original: String = "tset") -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: id,
        range: range,
        original: original,
        primaryReplacement: "test",
        allReplacements: ["test"],
        message: "Spelling error.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

// MARK: - AppDelegate Overlay Wiring Tests

/// Verifies the callback wiring logic AppDelegate applies to OverlayController.
/// Tests simulate what AppDelegate.applicationDidFinishLaunching wires up,
/// without instantiating AppDelegate (which requires a running NSApplication).
@MainActor
@Suite("AppDelegate overlay wiring")
struct AppDelegateWiringTests {

    @Test("onAcceptSuggestion callback removes suggestion from tracking array")
    func acceptCallbackRemovesSuggestion() {
        var suggestions = [makeWiringSuggestion(original: "aaa"), makeWiringSuggestion(original: "bbb")]
        let controller = OverlayController(accessor: MockAXAccessor())

        // Wire the same callback AppDelegate wires
        controller.onAcceptSuggestion = { suggestion in
            suggestions.removeAll { $0.id == suggestion.id }
        }

        let first = suggestions[0]
        controller.onAcceptSuggestion?(first)
        #expect(suggestions.count == 1)
        #expect(suggestions[0].original == "bbb")
    }

    @Test("onDismissSuggestion callback removes suggestion from tracking array")
    func dismissCallbackRemovesSuggestion() {
        var suggestions = [makeWiringSuggestion(original: "aaa"), makeWiringSuggestion(original: "bbb")]
        let controller = OverlayController(accessor: MockAXAccessor())

        controller.onDismissSuggestion = { suggestion in
            suggestions.removeAll { $0.id == suggestion.id }
        }

        let first = suggestions[0]
        controller.onDismissSuggestion?(first)
        #expect(suggestions.count == 1)
        #expect(suggestions[0].original == "bbb")
    }

    @Test("onAddToDictionary callback invokes harperService.addToDictionary with the word")
    func addToDictionaryCallsHarperService() async {
        let mockChecker = MockGrammarChecker()
        let controller = OverlayController(accessor: MockAXAccessor())

        controller.onAddToDictionary = { word in
            Task { await mockChecker.addToDictionary(word: word) }
        }

        controller.onAddToDictionary?("tset")
        // Allow the async task spawned in the callback to complete
        try? await Task.sleep(for: .milliseconds(200))
        #expect(mockChecker.addedWords.contains("tset"))
    }

    @Test("onDismissAll callback resets state tracking variables")
    func dismissAllResetsState() {
        var lastSuggestions: [Suggestion] = [makeWiringSuggestion()]
        var lastContext: TextContext? = TextContext(
            text: "tset",
            bundleID: "com.test",
            extractionMethod: .axDirectSelection,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
        var isIdle = false

        let controller = OverlayController(accessor: MockAXAccessor())
        controller.onDismissAll = {
            lastSuggestions = []
            lastContext = nil
            isIdle = true
        }

        controller.onDismissAll?()
        #expect(lastSuggestions.isEmpty)
        #expect(lastContext == nil)
        #expect(isIdle == true)
    }

    @Test("dismiss() triggers onDismissAll callback")
    func dismissFiresOnDismissAll() {
        var dismissed = false
        let controller = OverlayController(accessor: MockAXAccessor())
        controller.onDismissAll = { dismissed = true }

        controller.dismiss()
        #expect(dismissed == true)
    }

    @Test("dismiss() leaves suggestions empty (re-trigger cleanup)")
    func dismissLeavesOverlayClean() {
        let controller = OverlayController(accessor: MockAXAccessor())
        controller.suggestions = [makeWiringSuggestion()]
        controller.dismiss()
        #expect(controller.suggestions.isEmpty)
    }

    @Test("OverlayController accepts scheduler and incrementalConfig DI args without crashing")
    func overlayControllerAcceptsPhase18DIArgs() {
        // Verifies the init overload compiles and constructs without crashing.
        // scheduler and textMonitor are nil (no live LLM in test context); the card
        // dispatch path will early-return on the nil guard — no side effects.
        let ctrl = OverlayController(
            accessor: MockAXAccessor(),
            scheduler: nil,
            textMonitor: nil,
            incrementalConfig: UserDefaultsIncrementalConfig()
        )
        #expect(ctrl.hiddenParagraphScalarRange == nil)
    }

    @Test("overlayController.show does not crash when called with valid suggestions and context")
    func showCalledWithNonEmptySuggestions() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeWiringSuggestion()
        let context = TextContext(
            text: "tset",
            bundleID: "com.apple.Notes",
            extractionMethod: .axDirectSelection,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
        // AX bounds queries will fail (no real element), so entries will be empty
        // and show() will return early -- no crash
        controller.show(suggestions: [suggestion], context: context)
        // Suggestions are set before bounds queries
        #expect(controller.suggestions.count == 1)
    }
}
