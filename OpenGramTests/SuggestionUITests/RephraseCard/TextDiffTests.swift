import Testing
@testable import OpenGramLib

@Suite("TextDiff")
struct TextDiffTests {

    @Test func identicalInputs_producesAllUnchanged() {
        let segs = TextDiff.segments(original: "the quick brown fox", revised: "the quick brown fox")
        #expect(segs.allSatisfy { if case .unchanged = $0 { return true } else { return false } })
        #expect(joinedUnchangedAndAdded(segs) == "the quick brown fox")
    }

    @Test func emptyOriginal_producesAllAdded() {
        let segs = TextDiff.segments(original: "", revised: "hello world")
        #expect(segs.count == 1)
        if case .added(let s) = segs[0] { #expect(s == "hello world") } else { Issue.record("expected .added") }
    }

    @Test func emptyRevised_producesAllRemoved() {
        let segs = TextDiff.segments(original: "hello world", revised: "")
        #expect(segs.count == 1)
        if case .removed(let s) = segs[0] { #expect(s == "hello world") } else { Issue.record("expected .removed") }
    }

    @Test func pureInsertion_midSentence() {
        let segs = TextDiff.segments(original: "the fox jumps", revised: "the quick fox jumps")
        // Rebuild revised from unchanged+added
        #expect(joinedUnchangedAndAdded(segs) == "the quick fox jumps")
        #expect(segs.contains { if case .added(let s) = $0 { return s == "quick" } else { return false } })
    }

    @Test func pureDeletion_midSentence() {
        let segs = TextDiff.segments(original: "the very quick fox", revised: "the quick fox")
        #expect(joinedUnchangedAndAdded(segs) == "the quick fox")
        #expect(segs.contains { if case .removed(let s) = $0 { return s == "very" } else { return false } })
    }

    @Test func substitution_producesRemovedAndAdded() {
        let segs = TextDiff.segments(original: "the quick fox", revised: "the lazy fox")
        #expect(segs.contains { if case .removed(let s) = $0 { return s == "quick" } else { return false } })
        #expect(segs.contains { if case .added(let s) = $0 { return s == "lazy" } else { return false } })
    }

    @Test func nonBreakingSpace_treatedAsWhitespace() {
        let nbsp = "\u{00A0}"
        let segs = TextDiff.segments(original: "hello\(nbsp)world", revised: "hello\(nbsp)world")
        // Should tokenize on NBSP: joined unchanged is original
        #expect(segs.allSatisfy { if case .unchanged = $0 { return true } else { return false } })
    }

    @Test func unicode_emoji_preservedAsTokens() {
        let segs = TextDiff.segments(original: "hello 🌍 world", revised: "hello 🌏 world")
        #expect(segs.contains { if case .removed(let s) = $0 { return s == "🌍" } else { return false } })
        #expect(segs.contains { if case .added(let s) = $0 { return s == "🌏" } else { return false } })
    }

    @Test func hedgingRewrite_keepsSharedWordsUnmarked() {
        let original = "I was wondering if maybe we could possibly consider changing the onboarding copy because it kind of feels a little confusing for new users. The current version says that the app"
        let revised = "We should consider updating the onboarding copy because it currently confuses new users. The existing version states that the app"

        let segs = TextDiff.segments(original: original, revised: revised)

        #expect(joinedUnchangedAndAdded(segs) == revised)
        #expect(segs.contains { if case .unchanged(let s) = $0 { return s.contains("consider") } else { return false } })
        #expect(segs.contains { if case .unchanged(let s) = $0 { return s.contains("the onboarding copy because") } else { return false } })
        #expect(segs.contains { if case .removed(let s) = $0 { return s.contains("I was wondering") } else { return false } })
        #expect(segs.contains { if case .added(let s) = $0 { return s.contains("We should") } else { return false } })
    }

    private func joinedUnchangedAndAdded(_ segs: [DiffSegment]) -> String {
        segs.compactMap { seg -> String? in
            switch seg {
            case .unchanged(let s), .added(let s): return s
            case .removed: return nil
            }
        }.joined(separator: " ")
    }
}
