import Testing
import Foundation
@testable import OpenGramLib

@Suite struct Phase20ParagraphSplitterTests {
    // MARK: - Stub cache

    private final class StubCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
        var stored: [String: String] = [:]
        func isSupported(bundleID: String, version: String?) -> Bool? { nil }
        func store(bundleID: String, version: String?, supported: Bool) {}
        func isNotificationReliable(bundleID: String) -> Bool? { nil }
        func storeNotificationReliability(bundleID: String, reliable: Bool) {}
        func separator(bundleID: String, version: String?) -> String? {
            stored["\(bundleID):\(version ?? "nil")"]
        }
        func storeSeparator(bundleID: String, version: String?, separator: String) {
            stored["\(bundleID):\(version ?? "nil")"] = separator
        }
    }

    private func makeSplitter() -> (ParagraphSplitter, StubCapabilityCache) {
        let cache = StubCapabilityCache()
        return (ParagraphSplitter(capabilityCache: cache), cache)
    }

    // MARK: - PLL-15a: double-newline

    @Test func splitsOnDoubleNewline() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "alpha\n\nbeta", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.count == 2)
        #expect(set.paragraphs.map(\.text) == ["alpha", "beta"])
    }

    // MARK: - PLL-15b: single-newline fallback

    @Test func splitsOnSingleNewline_whenNoDoubleNewline() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "alpha\nbeta", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.count == 2)
        #expect(set.paragraphs.map(\.text) == ["alpha", "beta"])
    }

    // MARK: - PLL-15c: trim

    @Test func trimsWhitespace() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "  alpha  \n\n  beta  ", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.map(\.text) == ["alpha", "beta"])
    }

    // MARK: - PLL-15d: empty filter

    @Test func filtersEmpty() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "alpha\n\n\n\nbeta", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.count == 2)
    }

    // MARK: - PLL-15e: caret identification

    @Test func identifiesCaretParagraph() {
        let (s, _) = makeSplitter()
        let text = "alpha\n\nbeta"
        // scalar indices: 0..4 alpha, 5 \n, 6 \n, 7..10 beta
        let set = s.split(text: text, bundleID: "b", version: nil, caretOffset: 8)
        #expect(set.caretParagraphHash != nil)
        #expect(set.caretParagraphHash == set.paragraphs[1].hash)
    }

    // MARK: - PLL-15f: caret in separator zone

    @Test func caretInSeparatorZone_returnsNil() {
        let (s, _) = makeSplitter()
        // caret at position 5 (first '\n' of the double-newline separator)
        let set = s.split(text: "alpha\n\nbeta", bundleID: "b", version: nil, caretOffset: 5)
        #expect(set.caretParagraphHash == nil)
    }

    // MARK: - PLL-15g: single-paragraph doc

    @Test func singleParagraphDoc() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "one paragraph, no separator", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.count == 1)
        #expect(set.paragraphs[0].text == "one paragraph, no separator")
    }

    // MARK: - Empty text

    @Test func emptyTextReturnsZeroParagraphs() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.isEmpty)
        #expect(set.caretParagraphHash == nil)
    }

    // MARK: - Separator probe caches

    @Test func probedSeparatorCachedInCapabilityCache() {
        let (s, cache) = makeSplitter()
        _ = s.split(text: "alpha\n\nbeta", bundleID: "com.a", version: "1", caretOffset: nil)
        #expect(cache.separator(bundleID: "com.a", version: "1") == "\n\n")
    }

    @Test func cachedSeparatorUsedOnSubsequentSplit() {
        let cache = StubCapabilityCache()
        cache.storeSeparator(bundleID: "com.a", version: "1", separator: "\n\n")
        let splitter = ParagraphSplitter(capabilityCache: cache)
        // Single-newline text, but cached separator is \n\n — so it should be ONE paragraph.
        let set = splitter.split(text: "alpha\nbeta", bundleID: "com.a", version: "1", caretOffset: nil)
        #expect(set.paragraphs.count == 1)
    }

    // MARK: - ParagraphSet carries bundleID

    @Test func paragraphSetCarriesBundleID() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "alpha", bundleID: "com.a", version: nil, caretOffset: nil)
        #expect(set.bundleID == "com.a")
        #expect(set.paragraphs[0].hash.bundleID == "com.a")
    }

    // MARK: - Emoji / CJK survive

    @Test func emojiAndCJKSurvive() {
        let (s, _) = makeSplitter()
        let set = s.split(text: "日本語\n\n🎉 party", bundleID: "b", version: nil, caretOffset: nil)
        #expect(set.paragraphs.count == 2)
        #expect(set.paragraphs[0].text == "日本語")
        #expect(set.paragraphs[1].text == "🎉 party")
    }
}
