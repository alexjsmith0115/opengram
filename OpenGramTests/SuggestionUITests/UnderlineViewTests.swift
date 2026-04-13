import Testing
import AppKit
import Foundation

@testable import OpenGramLib

// MARK: - Helpers

private func makeSuggestion(
    category: CheckCategory = .spelling,
    source: SuggestionSource = .harper
) -> Suggestion {
    let text = "hello"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: nil,
        allReplacements: [],
        message: "test",
        category: category,
        source: source,
        priority: 0
    )
}

private func makeEntry(
    underlineRect: NSRect = NSRect(x: 10, y: 5, width: 50, height: 2),
    category: CheckCategory = .spelling,
    source: SuggestionSource = .harper
) -> UnderlineEntry {
    let suggestion = makeSuggestion(category: category, source: source)
    let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
    return UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion)
}

// MARK: - Tests

@Suite("UnderlineView static helpers")
struct UnderlineViewStaticTests {

    @Test("colorForCategory returns systemRed for spelling")
    func colorForCategorySpelling() {
        #expect(UnderlineView.colorForCategory(.spelling) == .systemRed)
    }

    @Test("colorForCategory returns systemBlue for grammarPunctuation")
    func colorForCategoryGrammar() {
        #expect(UnderlineView.colorForCategory(.grammarPunctuation) == .systemBlue)
    }

    @Test("isDashedForSource returns false for harper")
    func isDashedHarperIsFalse() {
        #expect(UnderlineView.isDashedForSource(.harper) == false)
    }

    @Test("isDashedForSource returns true for llm")
    func isDashedLLMIsTrue() {
        #expect(UnderlineView.isDashedForSource(.llm) == true)
    }

    @Test("expandedHitRect adds 6pt above and 6pt below (height += 12, y -= 6)")
    func expandedHitRectDimensions() {
        let underlineRect = NSRect(x: 10, y: 20, width: 80, height: 2)
        let hitRect = UnderlineView.expandedHitRect(from: underlineRect)

        #expect(hitRect.origin.x == 10)
        #expect(hitRect.origin.y == 14)         // 20 - 6
        #expect(hitRect.width == 80)
        #expect(hitRect.height == 14)           // 2 + 12
    }

    @Test("expandedHitRect width is unchanged")
    func expandedHitRectWidthUnchanged() {
        let underlineRect = NSRect(x: 5, y: 100, width: 120, height: 2)
        let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
        #expect(hitRect.width == 120)
    }
}

@Suite("UnderlineView entries and suggestions")
@MainActor
struct UnderlineViewEntryTests {

    @Test("entries array defaults to empty")
    func entriesDefaultEmpty() {
        let view = UnderlineView()
        #expect(view.entries.isEmpty)
    }

    @Test("focusedIndex defaults to nil")
    func focusedIndexDefaultsToNil() {
        let view = UnderlineView()
        #expect(view.focusedIndex == nil)
    }

    @Test("suggestionAt returns correct suggestion when point is inside hit rect")
    func suggestionAtInsideHitRect() {
        let view = UnderlineView()
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 5, width: 50, height: 2))
        view.entries = [entry]

        // Point inside the hit rect (hitRect.origin.y = 5-6 = -1, height = 14 → y range: -1..13)
        let insidePoint = NSPoint(x: 35, y: 5)
        let found = view.suggestionAt(point: insidePoint)
        #expect(found != nil)
        #expect(found?.id == entry.suggestion.id)
    }

    @Test("suggestionAt returns nil when point is outside all hit rects")
    func suggestionAtOutsideReturnsNil() {
        let view = UnderlineView()
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 5, width: 50, height: 2))
        view.entries = [entry]

        let outsidePoint = NSPoint(x: 200, y: 200)
        let found = view.suggestionAt(point: outsidePoint)
        #expect(found == nil)
    }

    @Test("stores array of UnderlineEntry with underlineRect, hitRect, suggestion")
    func entryStorageFields() {
        let underlineRect = NSRect(x: 20, y: 30, width: 60, height: 2)
        let suggestion = makeSuggestion(category: .grammarPunctuation)
        let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
        let entry = UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion)

        let view = UnderlineView()
        view.entries = [entry]

        #expect(view.entries.count == 1)
        #expect(view.entries[0].underlineRect == underlineRect)
        #expect(view.entries[0].hitRect == hitRect)
        #expect(view.entries[0].suggestion.category == .grammarPunctuation)
    }
}

@Suite("UnderlineView hitTest passthrough")
@MainActor
struct UnderlineViewHitTestTests {

    @Test("hitTest returns self when point is inside a hit rect")
    func hitTestInsideHitRectReturnsSelf() {
        let view = UnderlineView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 40, width: 80, height: 2))
        view.entries = [entry]

        // The hitRect is expandedHitRect: y = 40-6=34, height = 14 → y range: 34..48
        // hitTest receives coordinates in superview space; since there's no superview,
        // superview?.convert returns nil, so we fall back to the raw point.
        // We pass a point already in view-local coordinates (no superview in tests).
        let insidePoint = NSPoint(x: 50, y: 40)
        let result = view.hitTest(insidePoint)
        #expect(result === view)
    }

    @Test("hitTest returns nil when point is outside all hit rects (passthrough)")
    func hitTestOutsideReturnsNil() {
        let view = UnderlineView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 40, width: 80, height: 2))
        view.entries = [entry]

        let outsidePoint = NSPoint(x: 150, y: 80)
        let result = view.hitTest(outsidePoint)
        #expect(result == nil)
    }

    @Test("hitTest with empty entries returns nil for any point")
    func hitTestEmptyEntriesReturnsNil() {
        let view = UnderlineView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)

        let result = view.hitTest(NSPoint(x: 50, y: 50))
        #expect(result == nil)
    }
}
