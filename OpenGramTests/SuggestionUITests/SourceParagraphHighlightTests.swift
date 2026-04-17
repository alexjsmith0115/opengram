import Testing
import AppKit
@testable import OpenGramLib

@MainActor
@Suite("SourceParagraphHighlight")
struct SourceParagraphHighlightTests {

    @Test func hitTest_alwaysReturnsNil() {
        let view = SourceParagraphHighlight(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        #expect(view.hitTest(NSPoint(x: 50, y: 10)) == nil)
    }

    @Test func wantsLayer_isTrue() {
        let view = SourceParagraphHighlight(frame: .zero)
        #expect(view.wantsLayer == true)
        #expect(view.layer?.cornerRadius == 4)
    }

    @Test func backgroundColor_isSystemBlue_lowAlpha() {
        let view = SourceParagraphHighlight(frame: .zero)
        // Compare via CGColor alpha component
        #expect(view.layer?.backgroundColor?.alpha ?? 0 < 0.15)
        #expect(view.layer?.backgroundColor?.alpha ?? 0 > 0.05)
    }
}
