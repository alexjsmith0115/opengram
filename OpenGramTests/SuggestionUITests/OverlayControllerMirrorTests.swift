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

    // PERF-12 Gap 1: accept synchronously rebuilds view.entries so AppKit has no
    // draw cycle where pre-accept entries paint over shifted text.
    @Test("accept synchronously rebuilds view.entries (no draw-cycle gap between accept and async applyBounds)")
    func accept_rebuildsViewEntriesSynchronously() async throws {
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
        let rectA = NSRect(x: 100, y: 500, width: 30, height: 14)
        let rectB = NSRect(x: 140, y: 500, width: 30, height: 14)
        let rectC = NSRect(x: 180, y: 500, width: 30, height: 14)
        controller.lastKnownRects[idA] = [rectA]
        controller.lastKnownRects[idB] = [rectB]
        controller.lastKnownRects[idC] = [rectC]

        // Seed a live underlineView so the sync rebuildUnderlineEntries at tail of
        // repositionAfterAccept has a view to mutate. Mirrors the show() pattern.
        let view = UnderlineView()
        let entries: [UnderlineEntry] = [
            UnderlineEntry(underlineRect: rectA, hitRect: UnderlineView.expandedHitRect(from: rectA), suggestion: seeded[0]),
            UnderlineEntry(underlineRect: rectB, hitRect: UnderlineView.expandedHitRect(from: rectB), suggestion: seeded[1]),
            UnderlineEntry(underlineRect: rectC, hitRect: UnderlineView.expandedHitRect(from: rectC), suggestion: seeded[2]),
        ]
        view.entries = entries
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        controller.underlineView = view

        // Pre-accept sanity.
        #expect(controller.underlineView?.entries.count == 3)

        wireAcceptPath(mock: mock, updatedText: "aaa XXX ccc")
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, axRectValue(CGRect(x: 180, y: 500, width: 30, height: 14)))

        // Accept middle (idB). SYNC assertion BEFORE draining the async tail —
        // this is the defining check: if the sync rebuildUnderlineEntries at
        // tail of repositionAfterAccept is missing, entries remain [idA, idB, idC]
        // until applyBounds fires async.
        controller.acceptSuggestion(seeded[1], context: controller.textContext!, replacementOverride: "XXX")

        let entriesJustAfterAccept = controller.underlineView?.entries ?? []
        let syncIDs = Set(entriesJustAfterAccept.map { $0.suggestion.id })
        // idB must be gone sync (accepted + rebuilt). idA must be present sync
        // (strictly-before survivor preserved via lastKnownRects). idC allowed
        // either way (cache invalidated → rebuildUnderlineEntries skips it until
        // async; if the async already landed, it's back — both acceptable).
        #expect(!syncIDs.contains(idB), "idB underline must be removed synchronously after accept")
        #expect(syncIDs.contains(idA), "idA (strictly-before survivor) must remain synchronously after accept")

        // Drain the async tail; reassert coherence.
        await controller.currentRepositionTask?.value
        let finalIDs = Set((controller.underlineView?.entries ?? []).map { $0.suggestion.id })
        #expect(finalIDs.contains(idA))
        #expect(!finalIDs.contains(idB))
    }

    // PERF-12 Gap 2: update() with diff.unchanged survivors places overlayWindow
    // at SCREEN-space union of lastKnownRects, NOT at LOCAL-space union of
    // underlineView.entries.
    @Test("update() with diff.unchanged survivors places overlayWindow in SCREEN space, not LOCAL space")
    func update_windowFrameOriginIsScreenSpaceForDiffUnchangedSurvivors() async throws {
        let idA = UUID(); let idB = UUID(); let idC = UUID()
        let mock = MockAXAccessor()
        let queue = AXCallQueue(accessor: mock)
        let controller = OverlayController(accessor: mock, axQueue: queue)

        // Build suggestions with ranges bound to the actual context text so that
        // computeScalarOffsets (called by update()) yields distinct offsets per id
        // matching the pre-seeded suggestionScalarOffsets. Without this, Swift's
        // cross-string String.Index use collapses keys and the diff classifies
        // survivors unpredictably.
        let text = "aaa bbb ccc"
        let scalars = text.unicodeScalars
        func rangeAt(_ start: Int, _ end: Int) -> Range<String.Index> {
            let s = scalars.index(scalars.startIndex, offsetBy: start).samePosition(in: text)!
            let e = scalars.index(scalars.startIndex, offsetBy: end).samePosition(in: text)!
            return s..<e
        }
        func mkSuggestion(id: UUID, original: String, range: Range<String.Index>) -> Suggestion {
            Suggestion(
                id: id, range: range, original: original,
                primaryReplacement: original, allReplacements: [original],
                message: "", category: .spelling, source: .harper,
                priority: 5, paragraphHash: nil
            )
        }
        let sA = mkSuggestion(id: idA, original: "aaa", range: rangeAt(0, 3))
        let sB = mkSuggestion(id: idB, original: "bbb", range: rangeAt(4, 7))
        let sC = mkSuggestion(id: idC, original: "ccc", range: rangeAt(8, 11))
        let seeded = [sA, sB, sC]

        controller.suggestions = seeded
        controller.suggestionScalarOffsets = [
            (scalarStart: 0, scalarLength: 3),
            (scalarStart: 4, scalarLength: 3),
            (scalarStart: 8, scalarLength: 3),
        ]
        controller.textContext = TextContext(
            text: text, bundleID: "com.apple.TextEdit",
            extractionMethod: .axDirectSelection, selectionRange: nil,
            elementBounds: nil, axElement: AXUIElementCreateSystemWide()
        )

        // Seed underline view with LOCAL-space entries (what a prior show()/update()
        // would have produced after toLocalEntries translation). Pre-fix, update()
        // reused these LOCAL entries → unionRect LOCAL → setFrame LOCAL. Post-fix,
        // update() ignores these and sources from lastKnownRects (SCREEN).
        let localRectA = NSRect(x: 0, y: 0, width: 30, height: 22)
        let localRectB = NSRect(x: 40, y: 0, width: 30, height: 22)
        let localRectC = NSRect(x: 80, y: 0, width: 30, height: 22)
        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(underlineRect: localRectA, hitRect: localRectA, suggestion: sA),
            UnderlineEntry(underlineRect: localRectB, hitRect: localRectB, suggestion: sB),
            UnderlineEntry(underlineRect: localRectC, hitRect: localRectC, suggestion: sC),
        ]
        view.frame = NSRect(x: 0, y: 0, width: 120, height: 22)
        controller.underlineView = view

        // Seed lastKnownRects with deterministic SCREEN-space rects.
        let rectA = NSRect(x: 200, y: 500, width: 30, height: 14)
        let rectB = NSRect(x: 240, y: 500, width: 30, height: 14)
        let rectC = NSRect(x: 280, y: 500, width: 30, height: 14)
        controller.lastKnownRects[idA] = [rectA]
        controller.lastKnownRects[idB] = [rectB]
        controller.lastKnownRects[idC] = [rectC]

        // Bring overlayWindow to front so update()'s isVisible guard passes.
        controller.overlayWindow.contentView = view
        controller.overlayWindow.setFrame(NSRect(x: 10, y: 10, width: 120, height: 22), display: false)
        controller.overlayWindow.orderFrontRegardless()
        #expect(controller.overlayWindow.isVisible)

        // Construct newSuggestions with only idA + idB (idC dropped → diff.removed
        // non-empty → bypasses update()'s early-return at line 336 AND sends idA/idB
        // through the diff.unchanged branch + buggy union/setFrame at 409-420).
        // Keep originals + category identical so SuggestionKey matches.
        let newSuggestions: [Suggestion] = [sA, sB]
        let ctx = controller.textContext!

        controller.update(suggestions: newSuggestions, context: ctx)

        // SCREEN-space origin assertion — the smoking gun.
        //   union(rectA, rectB) = (x=200, y=500, w=70, h=14)
        //   hitRect expansion via UnderlineView.expandedHitRect adds vertical
        //   padding around the 2pt underline row, so we assert on padded
        //   union origin ignoring exact height/width.
        // Pre-fix (buggy): survivingEntries sourced from view.entries (LOCAL),
        // union lands near (x≈0, y≈0). Post-fix: SCREEN, lands near (x≈196, y near 500).
        let frame = controller.overlayWindow.frame
        #expect(frame.minX > 150, "expected SCREEN-space x > 150 (near 196), got \(frame.minX) — Gap 2 regression")
        #expect(frame.minX < 250, "expected SCREEN-space x < 250 (near 196), got \(frame.minX)")
        #expect(frame.minY > 400, "expected SCREEN-space y > 400 (near 500), got \(frame.minY) — Gap 2 regression")
    }

    // PERF-12 GAP-2: zero-AX early-bail inside reposition() must recompute the
    // overlay frame BEFORE rebuilding underline entries — mirrors the invariant
    // applyBounds + repositionAfterAccept already enforce. On this branch all
    // survivors are strictly-before the edit site, so union minX is anchored by
    // the leftmost survivor pre- and post-accept; LOCAL translation produces
    // identical entries in either order. The ordering defect is defensive-
    // correctness-only, so the regression lock is a source-position check.
    // Precedent: OverlayControllerRepositionTests.scrollPathCancels uses the
    // same approach because NSEvent global monitors aren't in-process observable.
    @Test("zero-AX early-bail recomputes frame before rebuilding entries (GAP-2 ordering invariant)")
    func zeroAXEarlyBail_recomputesFrameBeforeRebuildingEntries() throws {
        // Walk up from the test file to the repo root, then into the source path.
        // `#filePath` is: <repo>/OpenGramTests/SuggestionUITests/OverlayControllerMirrorTests.swift
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SuggestionUITests
            .deletingLastPathComponent()   // OpenGramTests
            .deletingLastPathComponent()   // <repo>
            .appendingPathComponent("OpenGram/SuggestionUI/Overlay/OverlayController.swift")

        let source = try String(contentsOf: url, encoding: .utf8)

        guard let anchorRange = source.range(of: "PERF-12 D-07") else {
            Issue.record("Anchor comment 'PERF-12 D-07' missing from OverlayController.swift — rebase or Task 1 unapplied")
            return
        }
        let tail = String(source[anchorRange.upperBound...])
        let snippet = String(tail.prefix(600))  // covers the block from comment through `return`

        guard let recomputeRange = snippet.range(of: "recomputeOverlayFrame()"),
              let rebuildRange = snippet.range(of: "rebuildUnderlineEntries()") else {
            Issue.record("Expected both recomputeOverlayFrame() and rebuildUnderlineEntries() within the zero-AX early-bail block")
            return
        }

        #expect(
            recomputeRange.lowerBound < rebuildRange.lowerBound,
            "GAP-2 regression: zero-AX early-bail must call recomputeOverlayFrame() BEFORE rebuildUnderlineEntries() — matches applyBounds + repositionAfterAccept invariant"
        )
    }
}
