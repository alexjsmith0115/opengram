import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

@Suite("AXRangeIndex")
struct AXRangeIndexTests {
    @Test("ASCII identity slice")
    func asciiSlice() {
        #expect(AXRangeIndex.substring(of: "hello", at: CFRange(location: 1, length: 3)) == "ell")
    }

    @Test("ASCII replacement")
    func asciiReplace() {
        #expect(AXRangeIndex.replacing(in: "hello", at: CFRange(location: 1, length: 3), with: "ipp") == "hippo")
    }

    @Test("Emoji slice (surrogate pair)")
    func emojiSlice() {
        let text = "Hi 👋 world"
        let slice = AXRangeIndex.substring(of: text, at: CFRange(location: 3, length: 2))
        #expect(slice == "👋")
    }

    @Test("Emoji replacement preserves surrounding text")
    func emojiReplace() {
        let text = "Hi 👋 world"
        let result = AXRangeIndex.replacing(in: text, at: CFRange(location: 3, length: 2), with: "🎉")
        #expect(result == "Hi 🎉 world")
    }

    @Test("Combining-mark slice (decomposed)")
    func combiningMark() {
        let decomposed = "cafe\u{0301}"
        let slice = AXRangeIndex.substring(of: decomposed, at: CFRange(location: 3, length: 2))
        #expect(slice == "e\u{0301}")
    }

    @Test("Surrogate-pair-splitting range returns nil")
    func surrogateSplit() {
        let text = "Hi 👋 world"
        #expect(AXRangeIndex.substring(of: text, at: CFRange(location: 3, length: 1)) == nil)
        #expect(AXRangeIndex.replacing(in: text, at: CFRange(location: 3, length: 1), with: "X") == nil)
    }

    @Test("Range beyond text length returns nil")
    func outOfBounds() {
        #expect(AXRangeIndex.substring(of: "hi", at: CFRange(location: 10, length: 1)) == nil)
        #expect(AXRangeIndex.substring(of: "hi", at: CFRange(location: 0, length: 100)) == nil)
    }

    @Test("Negative location returns nil")
    func negative() {
        #expect(AXRangeIndex.substring(of: "hi", at: CFRange(location: -1, length: 1)) == nil)
    }
}
