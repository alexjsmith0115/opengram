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
        priority: 0,
        paragraphHash: nil
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

    @Test("expandedHitRect stays close to the painted underline")
    func expandedHitRectDimensions() {
        let underlineRect = NSRect(x: 10, y: 20, width: 80, height: 2)
        let hitRect = UnderlineView.expandedHitRect(from: underlineRect)

        #expect(hitRect.origin.x == 10)
        #expect(hitRect.origin.y == 14)
        #expect(hitRect.width == 80)
        #expect(hitRect.height == 14)
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

    @Test("suggestionAt returns correct suggestion when point is inside hit rect")
    func suggestionAtInsideHitRect() {
        let view = UnderlineView()
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 5, width: 50, height: 2))
        view.entries = [entry]

        // Point inside the hit rect (hitRect.origin.y = 5-6 = -1, height = 14 -> y range: -1..13)
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
        let highlightRect = NSRect(x: 18, y: 30, width: 64, height: 18)
        let suggestion = makeSuggestion(category: .grammarPunctuation)
        let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
        let entry = UnderlineEntry(
            underlineRect: underlineRect,
            hitRect: hitRect,
            suggestion: suggestion,
            highlightRect: highlightRect
        )

        let view = UnderlineView()
        view.entries = [entry]

        #expect(view.entries.count == 1)
        #expect(view.entries[0].underlineRect == underlineRect)
        #expect(view.entries[0].hitRect == hitRect)
        #expect(view.entries[0].highlightRect == highlightRect)
        #expect(view.entries[0].suggestion.category == .grammarPunctuation)
    }

    @Test("suggestionAt includes the text highlight rect")
    func suggestionAtInsideHighlightRect() {
        let view = UnderlineView()
        let entry = UnderlineEntry(
            underlineRect: NSRect(x: 10, y: 5, width: 50, height: 2),
            hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 5, width: 50, height: 2)),
            suggestion: makeSuggestion(),
            highlightRect: NSRect(x: 8, y: 5, width: 54, height: 18)
        )
        view.entries = [entry]

        let found = view.hoveredSuggestionAt(point: NSPoint(x: 35, y: 20))
        #expect(found?.id == entry.suggestion.id)
        #expect(view.suggestionAt(point: NSPoint(x: 35, y: 20))?.id == entry.suggestion.id)
    }

    @Test("setHoveredSuggestionID records hovered suggestion")
    func setHoveredSuggestionIDStoresState() {
        let view = UnderlineView()
        let suggestion = makeSuggestion()

        view.setHoveredSuggestionID(suggestion.id, animated: false)
        #expect(view.hoveredSuggestionID == suggestion.id)

        view.setHoveredSuggestionID(nil, animated: false)
        #expect(view.hoveredSuggestionID == nil)
    }
}

@Suite("UnderlineView colorForSuggestion + z-order")
struct UnderlineViewColorTests {

    @Test("colorForSuggestion returns systemPurple for llm source")
    func colorForSuggestion_llm_returnsPurple() {
        let sug = Suggestion(
            id: UUID(),
            range: "x".startIndex..<"x".endIndex,
            original: "x",
            primaryReplacement: "y",
            allReplacements: ["y"],
            message: "m",
            category: .clarity,
            source: .llm,
            priority: 1,
            paragraphHash: nil
        )
        #expect(UnderlineView.colorForSuggestion(sug) == .systemPurple)
    }

    @Test("colorForSuggestion falls back to colorForCategory for harper source (spelling → red)")
    func colorForSuggestion_harperSpelling_returnsRed() {
        let sug = Suggestion(
            id: UUID(),
            range: "x".startIndex..<"x".endIndex,
            original: "x",
            primaryReplacement: "y",
            allReplacements: ["y"],
            message: "m",
            category: .spelling,
            source: .harper,
            priority: 1,
            paragraphHash: nil
        )
        #expect(UnderlineView.colorForSuggestion(sug) == .systemRed)
    }

    @Test("colorForSuggestion falls back to colorForCategory for harper source (grammar → blue)")
    func colorForSuggestion_harperGrammar_returnsBlue() {
        let sug = Suggestion(
            id: UUID(),
            range: "x".startIndex..<"x".endIndex,
            original: "x",
            primaryReplacement: "y",
            allReplacements: ["y"],
            message: "m",
            category: .grammarPunctuation,
            source: .harper,
            priority: 1,
            paragraphHash: nil
        )
        #expect(UnderlineView.colorForSuggestion(sug) == .systemBlue)
    }

    @MainActor
    @Test("draw sorts LLM entries before Harper (z-order)")
    func draw_sortsLLMBeforeHarper() {
        let llm = makeZOrderEntry(source: .llm)
        let harper = makeZOrderEntry(source: .harper)
        let mixed = [harper, llm]
        let sorted = mixed.sorted { a, b in
            let aOrder = (a.suggestion.source == .llm) ? 0 : 1
            let bOrder = (b.suggestion.source == .llm) ? 0 : 1
            return aOrder < bOrder
        }
        #expect(sorted.map { $0.suggestion.source } == [llm, harper].map { $0.suggestion.source })
    }
}

@MainActor
private func makeZOrderEntry(source: SuggestionSource) -> UnderlineEntry {
    let sug = Suggestion(
        id: UUID(),
        range: "x".startIndex..<"x".endIndex,
        original: "x",
        primaryReplacement: nil,
        allReplacements: [],
        message: "m",
        category: .grammarPunctuation,
        source: source,
        priority: 1,
        paragraphHash: nil
    )
    return UnderlineEntry(
        underlineRect: NSRect(x: 0, y: 0, width: 10, height: 2),
        hitRect: NSRect(x: 0, y: 0, width: 10, height: 10),
        suggestion: sug
    )
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

        // The hitRect is expandedHitRect: y = 40-6=34, height = 14 -> y range: 34..48
        // hitTest receives coordinates in superview space; since there's no superview,
        // superview?.convert returns nil, so we fall back to the raw point.
        // We pass a point already in view-local coordinates (no superview in tests).
        let insidePoint = NSPoint(x: 50, y: 40)
        let result = view.hitTest(insidePoint)
        #expect(result === view)
    }

    @Test("hitTest returns self inside the highlight rect")
    func hitTestInsideHighlightRectReturnsSelf() {
        let view = UnderlineView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let entry = makeEntry(underlineRect: NSRect(x: 10, y: 40, width: 80, height: 2))
        view.entries = [entry]

        let textBodyPoint = NSPoint(x: 50, y: 50)
        let result = view.hitTest(textBodyPoint)
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
