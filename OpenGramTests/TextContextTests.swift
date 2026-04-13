import Testing
@preconcurrency import ApplicationServices

@testable import OpenGram

@Suite("TextContext struct validation")
struct TextContextTests {

    @Test("TextContext initializes with all required fields")
    func initializesWithAllFields() {
        let dummyElement = AXUIElementCreateSystemWide()
        let range = CFRange(location: 5, length: 10)
        let bounds = CGRect(x: 100, y: 200, width: 300, height: 50)

        let context = TextContext(
            text: "Hello world",
            bundleID: "com.apple.Notes",
            extractionMethod: .axDirectSelection,
            selectionRange: range,
            elementBounds: bounds,
            axElement: dummyElement
        )

        #expect(context.text == "Hello world")
        #expect(context.bundleID == "com.apple.Notes")
        #expect(context.extractionMethod == .axDirectSelection)
        #expect(context.selectionRange?.location == 5)
        #expect(context.selectionRange?.length == 10)
        #expect(context.elementBounds?.origin.x == 100)
        #expect(context.elementBounds?.origin.y == 200)
        #expect(context.elementBounds?.width == 300)
        #expect(context.elementBounds?.height == 50)
    }

    @Test("ExtractionMethod.axDirectSelection has correct raw value")
    func axDirectSelectionRawValue() {
        #expect(ExtractionMethod.axDirectSelection.rawValue == "ax-direct-selection")
    }

    @Test("ExtractionMethod.axDirectFull has correct raw value")
    func axDirectFullRawValue() {
        #expect(ExtractionMethod.axDirectFull.rawValue == "ax-direct-full")
    }

    @Test("TextContext initializes with nil optional fields")
    func initializesWithNilOptionals() {
        let dummyElement = AXUIElementCreateSystemWide()

        let context = TextContext(
            text: "Test",
            bundleID: "com.example.app",
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            axElement: dummyElement
        )

        #expect(context.selectionRange == nil)
        #expect(context.elementBounds == nil)
    }
}
