import Testing
import Foundation
@testable import OpenGramLib

@Suite struct ParagraphHashTests {
    @Test func sha256IsFull64CharHex() {
        let h = ParagraphHash(bundleID: "b", paragraphText: "hello")
        #expect(h.sha256.count == 64)
        #expect(h.sha256.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func whitespaceOnlyDiffYieldsSameHash() {
        let a = ParagraphHash(bundleID: "b", paragraphText: "hello  world")
        let b = ParagraphHash(bundleID: "b", paragraphText: "hello world")
        let c = ParagraphHash(bundleID: "b", paragraphText: "  hello world  ")
        #expect(a == b)
        #expect(b == c)
    }

    @Test func caseDiffYieldsDifferentHash() {
        let a = ParagraphHash(bundleID: "b", paragraphText: "Hello")
        let b = ParagraphHash(bundleID: "b", paragraphText: "hello")
        #expect(a != b)
    }

    @Test func punctuationDiffYieldsDifferentHash() {
        let a = ParagraphHash(bundleID: "b", paragraphText: "hello.")
        let b = ParagraphHash(bundleID: "b", paragraphText: "hello")
        #expect(a != b)
    }

    @Test func bundleIDPartitionsCollisionDomain() {
        let a = ParagraphHash(bundleID: "com.app.a", paragraphText: "same text")
        let b = ParagraphHash(bundleID: "com.app.b", paragraphText: "same text")
        #expect(a != b)
        #expect(a.sha256 == b.sha256)
    }

    @Test func deterministicForFixedInput() {
        let text = "The quick brown fox."
        let a = ParagraphHash(bundleID: "b", paragraphText: text)
        let b = ParagraphHash(bundleID: "b", paragraphText: text)
        #expect(a.sha256 == b.sha256)
    }

    @Test func escapeHatchInitPreservesValue() {
        let h = ParagraphHash(bundleID: "x", sha256: "deadbeef")
        #expect(h.bundleID == "x")
        #expect(h.sha256 == "deadbeef")
    }
}
