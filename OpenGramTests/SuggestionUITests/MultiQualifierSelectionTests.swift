import Testing
import Foundation
@testable import OpenGramLib

@MainActor
@Suite("OverlayController.selectQualifier")
struct MultiQualifierSelectionTests {

    private func makeQ(text: String, startIndex: Int, in source: String) -> CardQualifier {
        let scalars = source.unicodeScalars
        let startSI = scalars.index(scalars.startIndex, offsetBy: startIndex)
        let endSI = scalars.index(startSI, offsetBy: text.unicodeScalars.count)
        let lower = startSI.samePosition(in: source) ?? source.startIndex
        let upper = endSI.samePosition(in: source) ?? source.endIndex
        let p = Paragraph(text: text, range: lower..<upper, index: 0)
        let hash = ParagraphHash(bundleID: "com.test", paragraphText: text)
        return CardQualifier(paragraph: p, llmIssues: [], harperInside: [], hash: hash, legacyHash: 0)
    }

    @Test func caretInsideFirst_picksFirst() {
        let source = "alpha beta gamma\n\ndelta epsilon zeta"
        let q1 = makeQ(text: "alpha beta gamma", startIndex: 0, in: source)
        let q2 = makeQ(text: "delta epsilon zeta", startIndex: 18, in: source)
        let sel = OverlayController.selectQualifier(qualifiers: [q1, q2], caretScalarIndex: 5, in: source)
        #expect(sel.paragraph.text == "alpha beta gamma")
    }

    @Test func caretInsideSecond_picksSecond() {
        let source = "alpha beta gamma\n\ndelta epsilon zeta"
        let q1 = makeQ(text: "alpha beta gamma", startIndex: 0, in: source)
        let q2 = makeQ(text: "delta epsilon zeta", startIndex: 18, in: source)
        let sel = OverlayController.selectQualifier(qualifiers: [q1, q2], caretScalarIndex: 25, in: source)
        #expect(sel.paragraph.text == "delta epsilon zeta")
    }

    @Test func caretBetweenParagraphs_picksNearestByMidpoint() {
        let source = "aaa\n\nbbbbb"
        let q1 = makeQ(text: "aaa", startIndex: 0, in: source)   // mid offset 1
        let q2 = makeQ(text: "bbbbb", startIndex: 5, in: source) // mid offset 7
        // caret=3 → |3-1|=2 < |3-7|=4 → q1 wins
        let sel = OverlayController.selectQualifier(qualifiers: [q1, q2], caretScalarIndex: 3, in: source)
        #expect(sel.paragraph.text == "aaa")
    }

    @Test func caretNil_picksFirst() {
        let source = "aaa\n\nbbbbb"
        let q1 = makeQ(text: "aaa", startIndex: 0, in: source)
        let q2 = makeQ(text: "bbbbb", startIndex: 5, in: source)
        let sel = OverlayController.selectQualifier(qualifiers: [q1, q2], caretScalarIndex: nil, in: source)
        #expect(sel.paragraph.text == "aaa")
    }
}
