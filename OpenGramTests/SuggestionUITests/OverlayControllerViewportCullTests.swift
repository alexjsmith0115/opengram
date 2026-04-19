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

    // PERF-12 D-09: .textChanged queries only cache-invalidated suggestions.
    // Strictly-before survivors whose rects are preserved stay out of the batch.
    @Test(".textChanged queries only uncached suggestions")
    func textChanged_queriesOnlyUncachedSuggestions() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, _, _) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])
        controller.lastKnownRects[idA] = [NSRect(x: 10, y: 100, width: 50, height: 14)]

        let result = controller.suggestionsForReposition(
            reason: .textChanged,
            context: controller.textContext!
        )
        // idA is cached — excluded from the batch. idB and idC are uncached — included.
        #expect(result.count == 2)
        #expect(Set(result.map(\.id)) == Set([idB, idC]))
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

    // PERF-12 D-05: acceptSuggestion invalidates lastKnownRects for overlapping
    // and after-edit suggestions (tightens the minimal-invalidation contract —
    // strictly-before survivors preserved; everything else invalidated).
    @Test("acceptSuggestion invalidates after-edit cache entries")
    func acceptInvalidatesAfterEditCacheEntries() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let (controller, mock, seeded) = makeViewportCullController(suggestionCount: 3, ids: [idA, idB, idC])

        // Non-overlapping offsets: idA at 0-7, idB at 10-17, idC at 20-27.
        // Accepting idA means idB and idC are both after-edit — both cache entries
        // must be invalidated under the D-05 predicate `beforeEnd > editStart`.
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

        // Wire kAXBoundsForRangeParameterizedAttribute so the async reposition tail's
        // boundsBatch can resolve rects for the two invalidated suggestions.
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, axRectValue(CGRect(x: 10, y: 100, width: 50, height: 14)))

        let ctx = controller.textContext!
        controller.acceptSuggestion(seeded[0], context: ctx, replacementOverride: "receive")

        // D-05 predicate runs SYNCHRONOUSLY inside repositionAfterAccept before the
        // async scheduleReposition tail. Assertions capture the post-sync, pre-async
        // state: all three entries invalidated (idA via accept eviction, idB and idC
        // via D-05 after-edit predicate).
        #expect(controller.lastKnownRects[idA] == nil)
        #expect(controller.lastKnownRects[idB] == nil)
        #expect(controller.lastKnownRects[idC] == nil)

        // Drain the async tail so the test doesn't leak a pending Task.
        await controller.currentRepositionTask?.value
    }
}
