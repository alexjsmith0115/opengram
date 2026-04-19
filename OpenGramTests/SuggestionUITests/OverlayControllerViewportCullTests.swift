import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

// MARK: - Helpers (inlined — OverlayControllerTests / OverlayControllerRepositionTests helpers are file-private)

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

private func makeTextContext(text: String = "recieve") -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
        axElement: AXUIElementCreateSystemWide()
    )
}

private func axPointValue(_ point: CGPoint) -> CFTypeRef {
    var p = point
    return AXValueCreate(.cgPoint, &p)!
}

private func axSizeValue(_ size: CGSize) -> CFTypeRef {
    var s = size
    return AXValueCreate(.cgSize, &s)!
}

private func axRectValue(_ rect: CGRect) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

/// Seeds a controller with N suggestions. Element-bounds mocks configured by caller
/// per test (position + size for `.scrollDuring`/`.scrollSettled` cull path).
@MainActor
private func makeViewportCullController(
    suggestionCount: Int,
    ids: [UUID]? = nil
) -> (controller: OverlayController, mock: MockAXAccessor, suggestions: [Suggestion]) {
    let mock = MockAXAccessor()
    let queue = AXCallQueue(accessor: mock)
    let controller = OverlayController(accessor: mock, axQueue: queue)
    let resolvedIDs = ids ?? (0..<suggestionCount).map { _ in UUID() }
    let seeded = resolvedIDs.map { makeSuggestion(id: $0) }
    controller.suggestions = seeded
    controller.textContext = makeTextContext()
    return (controller, mock, seeded)
}

// MARK: - Tests

@Suite("OverlayController viewport cull")
@MainActor
struct OverlayControllerViewportCullTests {

    // PERF-06: .scrollDuring culls offscreen cached suggestions against padded element bounds.
    @Test(".scrollDuring filters offscreen cached suggestions")
    func scrollDuring_filtersOffscreenCachedSuggestions() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, mock, _) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])

        // Element bounds origin=(0,80) size=(800,200) → padded Y range 40..320 (padding=40).
        mock.attributeValues[kAXPositionAttribute] = (.success, axPointValue(CGPoint(x: 0, y: 80)))
        mock.attributeValues[kAXSizeAttribute] = (.success, axSizeValue(CGSize(width: 800, height: 200)))

        // Cached rects — A inside padded range, B & C outside.
        controller.lastKnownRects[idA] = [NSRect(x: 10, y: 100, width: 50, height: 14)]
        controller.lastKnownRects[idB] = [NSRect(x: 10, y: 500, width: 50, height: 14)]
        controller.lastKnownRects[idC] = [NSRect(x: 10, y: 900, width: 50, height: 14)]

        let result = controller.suggestionsForReposition(
            reason: .scrollDuring,
            context: controller.textContext!
        )
        #expect(result.map(\.id) == [idA])
    }

    // PERF-06: .initial returns all suggestions regardless of cache state.
    @Test(".initial queries all regardless of cache")
    func initial_queriesAllRegardlessOfCache() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, _, _) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])

        // Only A cached; B and C absent. .initial must still return all three.
        controller.lastKnownRects[idA] = [NSRect(x: 10, y: 100, width: 50, height: 14)]

        let result = controller.suggestionsForReposition(
            reason: .initial,
            context: controller.textContext!
        )
        #expect(result.count == 3)
        #expect(Set(result.map(\.id)) == Set([idA, idB, idC]))
    }

    // PERF-06: .textChanged returns all suggestions regardless of cache state.
    @Test(".textChanged queries all regardless of cache")
    func textChanged_queriesAllRegardlessOfCache() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, _, _) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])
        controller.lastKnownRects[idA] = [NSRect(x: 10, y: 100, width: 50, height: 14)]

        let result = controller.suggestionsForReposition(
            reason: .textChanged,
            context: controller.textContext!
        )
        #expect(result.count == 3)
        #expect(Set(result.map(\.id)) == Set([idA, idB, idC]))
    }

    // PERF-05: dismiss() empties lastKnownRects.
    @Test("dismiss clears lastKnownRects")
    func dismissClearsLastKnownRects() async throws {
        let idA = UUID(); let idB = UUID()
        let (controller, _, _) = makeViewportCullController(suggestionCount: 2, ids: [idA, idB])
        controller.lastKnownRects[idA] = [NSRect(x: 0, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idB] = [NSRect(x: 0, y: 20, width: 10, height: 2)]

        controller.dismiss()

        #expect(controller.lastKnownRects.isEmpty)
    }

    // PERF-05: acceptSuggestion removes only the accepted ID from lastKnownRects.
    // Mock wired for deterministic write-path success (kAXSelectedTextRangeAttribute settable
    // + both set calls return .success). kAXValueAttribute and kAXBoundsForRangeParameterizedAttribute
    // wired so repositionAfterAccept does not call dismiss() and invalidate the assertion.
    @Test("acceptSuggestion removes only the accepted ID")
    func acceptRemovesOnlyAcceptedID() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, mock, seeded) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])

        // Non-overlapping offsets: idA at 0-7, idB at 10-17, idC at 20-27.
        // repositionAfterAccept marks suggestions as overlapping when scalarRanges intersect
        // the accepted range — identical offsets would zero out idB and idC, causing dismiss().
        controller.suggestionScalarOffsets = [
            (scalarStart: 0,  scalarLength: 7),
            (scalarStart: 10, scalarLength: 7),
            (scalarStart: 20, scalarLength: 7),
        ]

        controller.lastKnownRects[idA] = [NSRect(x: 0, y: 0, width: 10, height: 2)]
        controller.lastKnownRects[idB] = [NSRect(x: 0, y: 20, width: 10, height: 2)]
        controller.lastKnownRects[idC] = [NSRect(x: 0, y: 40, width: 10, height: 2)]

        // AXTextReplacer primary-path success: isAttributeSettable + both setAttributeValue calls.
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.setAttributeResult = .success

        // repositionAfterAccept reads kAXValueAttribute for updated text. Provide a 27-char
        // string so rangeFromCharOffsets(start:10, end:17) and (start:20, end:27) stay in bounds.
        let updatedText = "receive   recieve   recieve"
        mock.attributeValues[kAXValueAttribute] = (.success, updatedText as CFString)

        // repositionAfterAccept re-queries bounds for remaining suggestions; wire a non-nil
        // rect so surviving suggestions produce entries and dismiss() is not called.
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, axRectValue(CGRect(x: 10, y: 100, width: 50, height: 14)))

        let ctx = controller.textContext!
        controller.acceptSuggestion(seeded[0], context: ctx, replacementOverride: "receive")

        // D-15 contract — strict assertions, no fallback, no hedging.
        #expect(controller.lastKnownRects[idA] == nil)
        #expect(controller.lastKnownRects[idB] != nil)
        #expect(controller.lastKnownRects[idC] != nil)
    }
}
