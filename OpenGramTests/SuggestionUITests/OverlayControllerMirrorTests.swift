import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

// MARK: - Helpers (inlined — mirror OverlayControllerViewportCullTests pattern)

private func makeSuggestion(
    id: UUID = UUID(),
    original: String = "recieve",
    primaryReplacement: String = "receive"
) -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: id,
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

private func makeTextContext(text: String = "aaa bbb ccc") -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
        axElement: AXUIElementCreateSystemWide()
    )
}

private func axRectValue(_ rect: CGRect) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

/// Seeds a controller with N suggestions + the provided text. AXCallQueue and
/// MockAXAccessor are wired for `@testable` inspection.
@MainActor
private func makeMirrorController(
    suggestionCount: Int,
    ids: [UUID]? = nil,
    text: String = "aaa bbb ccc"
) -> (controller: OverlayController, mock: MockAXAccessor, queue: AXCallQueue, suggestions: [Suggestion]) {
    let mock = MockAXAccessor()
    let queue = AXCallQueue(accessor: mock)
    let controller = OverlayController(accessor: mock, axQueue: queue)
    let resolvedIDs = ids ?? (0..<suggestionCount).map { _ in UUID() }
    let seeded = resolvedIDs.map { makeSuggestion(id: $0) }
    controller.suggestions = seeded
    controller.textContext = makeTextContext(text: text)
    return (controller, mock, queue, seeded)
}

/// Configures `mock` for a successful range-targeted AX write + post-accept text re-read.
/// `updatedText` is the string `kAXValueAttribute` returns after the write. Callers wire
/// `kAXBoundsForRangeParameterizedAttribute` themselves per test (absent = zero-AX path).
private func wireAcceptPath(mock: MockAXAccessor, updatedText: String) {
    mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
    mock.setAttributeResult = .success
    mock.attributeValues[kAXValueAttribute] = (.success, updatedText as CFString)
}

// MARK: - Tests

@Suite("OverlayController session-local mirror")
@MainActor
struct OverlayControllerMirrorTests {

    // PERF-12 D-09: .textChanged filter returns only suggestions with no cached rects.
    @Test(".textChanged filter returns only suggestions with no cached rects")
    func textChanged_queriesOnlyInvalidated() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, _, _, _) = makeMirrorController(suggestionCount: 3, ids: [idA, idB, idC])

        // Cache A and C; leave B uncached.
        controller.lastKnownRects[idA] = [NSRect(x: 0, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idC] = [NSRect(x: 0, y: 40, width: 10, height: 2)]

        let result = controller.suggestionsForReposition(
            reason: .textChanged,
            context: controller.textContext!
        )

        #expect(result.map(\.id) == [idB])
    }

    // PERF-12 D-05: accepting a suggestion preserves lastKnownRects for suggestions
    // whose pre-shift scalar range ends at or before the edit site.
    @Test("accept preserves cache for strictly-before suggestions")
    func accept_preservesCacheForEarlierSuggestions() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, mock, _, seeded) = makeMirrorController(
            suggestionCount: 3, ids: [idA, idB, idC], text: "aaa bbb ccc"
        )

        // idA at 0-3 (strictly before idB), idB at 4-7 (accept target), idC at 8-11 (after edit).
        controller.suggestionScalarOffsets = [
            (scalarStart: 0, scalarLength: 3),
            (scalarStart: 4, scalarLength: 3),
            (scalarStart: 8, scalarLength: 3),
        ]
        let rectA = NSRect(x: 0, y: 0, width: 10, height: 2)
        controller.lastKnownRects[idA] = [rectA]
        controller.lastKnownRects[idB] = [NSRect(x: 20, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idC] = [NSRect(x: 40, y: 0, width: 10, height: 2)]

        wireAcceptPath(mock: mock, updatedText: "aaa XXX ccc")
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, axRectValue(CGRect(x: 40, y: 0, width: 10, height: 2)))

        controller.acceptSuggestion(seeded[1], context: controller.textContext!, replacementOverride: "XXX")
        await controller.currentRepositionTask?.value

        #expect(controller.lastKnownRects[idA] == [rectA])
    }

    // PERF-12 D-05: accepting a suggestion invalidates lastKnownRects for overlapping
    // and after-edit suggestions (predicate `beforeEnd > editStart`).
    @Test("accept invalidates cache for after-edit suggestions")
    func accept_invalidatesCacheForLaterSuggestions() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, mock, _, seeded) = makeMirrorController(
            suggestionCount: 3, ids: [idA, idB, idC], text: "aaa bbb ccc"
        )

        // idA at 0-3 (accept target), idB at 4-7 (after edit), idC at 8-11 (after edit).
        controller.suggestionScalarOffsets = [
            (scalarStart: 0, scalarLength: 3),
            (scalarStart: 4, scalarLength: 3),
            (scalarStart: 8, scalarLength: 3),
        ]
        controller.lastKnownRects[idA] = [NSRect(x: 0, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idB] = [NSRect(x: 20, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idC] = [NSRect(x: 40, y: 0, width: 10, height: 2)]

        wireAcceptPath(mock: mock, updatedText: "XXX bbb ccc")
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, axRectValue(CGRect(x: 0, y: 0, width: 10, height: 2)))

        controller.acceptSuggestion(seeded[0], context: controller.textContext!, replacementOverride: "XXX")

        // D-05 runs SYNCHRONOUSLY in repositionAfterAccept before scheduleReposition spawns
        // the async tail. Assert the post-sync, pre-async state: all after-edit rects gone.
        #expect(controller.lastKnownRects[idA] == nil)
        #expect(controller.lastKnownRects[idB] == nil)
        #expect(controller.lastKnownRects[idC] == nil)

        // Drain so the test doesn't leak a pending Task.
        await controller.currentRepositionTask?.value
    }

    // PERF-12 D-07: end-of-doc accept with all survivors strictly before the edit site
    // issues zero axQueue.boundsBatch invocations (headline optimization).
    @Test("accept at end of doc issues zero bounds queries")
    func accept_zeroAXCallOnEndEdit() async throws {
        let idA = UUID(); let idB = UUID()
        let (controller, mock, queue, _) = makeMirrorController(
            suggestionCount: 2, ids: [idA, idB], text: "aaa bbb cc"
        )

        // idA at 0-3, idB at 4-7. Both strictly before the accept target.
        controller.suggestionScalarOffsets = [
            (scalarStart: 0, scalarLength: 3),
            (scalarStart: 4, scalarLength: 3),
        ]
        let rectA = NSRect(x: 0, y: 0, width: 10, height: 2)
        let rectB = NSRect(x: 20, y: 0, width: 10, height: 2)
        controller.lastKnownRects[idA] = [rectA]
        controller.lastKnownRects[idB] = [rectB]

        // Append synthetic trailing suggestion at end-of-doc [8..10]. No cached rect for it.
        let trailingID = UUID()
        let trailing = makeSuggestion(id: trailingID, original: "cc", primaryReplacement: "XX")
        controller.suggestions.append(trailing)
        controller.suggestionScalarOffsets.append((scalarStart: 8, scalarLength: 2))

        wireAcceptPath(mock: mock, updatedText: "aaa bbb XX")
        // Deliberately DO NOT wire kAXBoundsForRangeParameterizedAttribute — zero-AX path
        // must not reach validator. If axQueue.boundsBatch is incorrectly invoked, the
        // call still completes (validator returns nil for all targets), but boundsBatchCallCount
        // increments and this test fails.

        let preCount = await queue.boundsBatchCallCount

        controller.acceptSuggestion(trailing, context: controller.textContext!, replacementOverride: "XX")
        await controller.currentRepositionTask?.value

        let postCount = await queue.boundsBatchCallCount

        #expect(postCount == preCount)
        #expect(controller.lastKnownRects[idA] == [rectA])
        #expect(controller.lastKnownRects[idB] == [rectB])
    }
}
