import Testing
import Foundation

@testable import OpenGramLib

// MARK: - Test helpers

private func makeSuggestion(
    original: String,
    category: CheckCategory = .grammarPunctuation
) -> Suggestion {
    // Use a dummy range backed by the original string
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: UUID(),
        range: range,
        original: original,
        primaryReplacement: nil,
        allReplacements: [],
        message: "test",
        category: category,
        source: .harper,
        priority: 0
    )
}

private func makeOffset(start: Int, length: Int) -> (scalarStart: Int, scalarLength: Int) {
    (scalarStart: start, scalarLength: length)
}

@Suite("SuggestionDiffEngine")
struct SuggestionDiffEngineTests {

    @Test("Identical suggestion sets produce zero additions, zero removals, all unchanged")
    func identicalSetsAllUnchanged() {
        let s1 = makeSuggestion(original: "teh", category: .spelling)
        let s2 = makeSuggestion(original: "teh", category: .spelling)
        let offset = makeOffset(start: 0, length: 3)

        let result = SuggestionDiffEngine.diff(
            old: [s1],
            oldOffsets: [offset],
            new: [s2],
            newOffsets: [offset]
        )

        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.unchanged.count == 1)
        #expect(result.unchanged[0].oldIndex == 0)
        #expect(result.unchanged[0].newIndex == 0)
    }

    @Test("New suggestion not in old set appears in added")
    func newSuggestionAppearsInAdded() {
        let old = makeSuggestion(original: "teh")
        let new1 = makeSuggestion(original: "teh")
        let new2 = makeSuggestion(original: "recieve")

        let result = SuggestionDiffEngine.diff(
            old: [old],
            oldOffsets: [makeOffset(start: 0, length: 3)],
            new: [new1, new2],
            newOffsets: [makeOffset(start: 0, length: 3), makeOffset(start: 10, length: 7)]
        )

        #expect(result.added.count == 1)
        #expect(result.added[0] == 1)
        #expect(result.removed.isEmpty)
        #expect(result.unchanged.count == 1)
    }

    @Test("Old suggestion not in new set appears in removed with its old index")
    func oldSuggestionAppearsInRemoved() {
        let old1 = makeSuggestion(original: "teh")
        let old2 = makeSuggestion(original: "recieve")
        let new1 = makeSuggestion(original: "teh")

        let result = SuggestionDiffEngine.diff(
            old: [old1, old2],
            oldOffsets: [makeOffset(start: 0, length: 3), makeOffset(start: 10, length: 7)],
            new: [new1],
            newOffsets: [makeOffset(start: 0, length: 3)]
        )

        #expect(result.removed.count == 1)
        #expect(result.removed[0] == 1)
        #expect(result.added.isEmpty)
        #expect(result.unchanged.count == 1)
    }

    @Test("Same offset with different original text is treated as removed+added")
    func differentOriginalAtSameOffsetIsRemovedAndAdded() {
        let old = makeSuggestion(original: "teh")
        let new = makeSuggestion(original: "thw")
        let offset = makeOffset(start: 0, length: 3)

        let result = SuggestionDiffEngine.diff(
            old: [old],
            oldOffsets: [offset],
            new: [new],
            newOffsets: [offset]
        )

        #expect(result.removed.count == 1)
        #expect(result.added.count == 1)
        #expect(result.unchanged.isEmpty)
    }

    @Test("Same original and offset but different category is treated as removed+added")
    func differentCategoryAtSameOffsetIsRemovedAndAdded() {
        let old = makeSuggestion(original: "test", category: .spelling)
        let new = makeSuggestion(original: "test", category: .grammarPunctuation)
        let offset = makeOffset(start: 0, length: 4)

        let result = SuggestionDiffEngine.diff(
            old: [old],
            oldOffsets: [offset],
            new: [new],
            newOffsets: [offset]
        )

        #expect(result.removed.count == 1)
        #expect(result.added.count == 1)
        #expect(result.unchanged.isEmpty)
    }

    @Test("Empty old set + non-empty new set = all added")
    func emptyOldAllAdded() {
        let s1 = makeSuggestion(original: "teh")
        let s2 = makeSuggestion(original: "recieve")

        let result = SuggestionDiffEngine.diff(
            old: [],
            oldOffsets: [],
            new: [s1, s2],
            newOffsets: [makeOffset(start: 0, length: 3), makeOffset(start: 10, length: 7)]
        )

        #expect(result.added.count == 2)
        #expect(result.added.contains(0))
        #expect(result.added.contains(1))
        #expect(result.removed.isEmpty)
        #expect(result.unchanged.isEmpty)
    }

    @Test("Non-empty old set + empty new set = all removed")
    func emptyNewAllRemoved() {
        let s1 = makeSuggestion(original: "teh")
        let s2 = makeSuggestion(original: "recieve")

        let result = SuggestionDiffEngine.diff(
            old: [s1, s2],
            oldOffsets: [makeOffset(start: 0, length: 3), makeOffset(start: 10, length: 7)],
            new: [],
            newOffsets: []
        )

        #expect(result.removed.count == 2)
        #expect(result.removed.contains(0))
        #expect(result.removed.contains(1))
        #expect(result.added.isEmpty)
        #expect(result.unchanged.isEmpty)
    }

    @Test("Both empty sets produce no changes")
    func bothEmptyNoChanges() {
        let result = SuggestionDiffEngine.diff(
            old: [],
            oldOffsets: [],
            new: [],
            newOffsets: []
        )

        #expect(result.added.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.unchanged.isEmpty)
    }
}
