import Testing
@preconcurrency import ApplicationServices
import AppKit
import Foundation

@testable import OpenGramLib

// MARK: - Helpers

private func makeSuggestion(in text: String, startChar: Int, endChar: Int) -> Suggestion? {
    guard let range = text.rangeFromCharOffsets(start: startChar, end: endChar) else { return nil }
    return Suggestion(
        id: .init(),
        range: range,
        original: String(text[range]),
        primaryReplacement: "fixed",
        allReplacements: ["fixed"],
        message: "test issue",
        category: .spelling,
        source: .harper,
        priority: 1
    )
}

// MARK: - Tests

@Suite("OverlayController boundsForRange")
@MainActor
struct BoundsForRangeTests {

    @Test("boundsForRange calls copyParameterizedAttributeValue with kAXBoundsForRangeParameterizedAttribute")
    func boundsForRangeCallsAX() throws {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)

        let text = "Hello world"
        let suggestion = try #require(makeSuggestion(in: text, startChar: 0, endChar: 5))
        let element = AXUIElementCreateSystemWide()

        // Set up mock to return nil (no value) — we're just checking the call is made
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.parameterizedAttributeUnsupported, nil)

        let result = controller.boundsForRange(suggestion, in: text, element: element)

        #expect(result == nil)
        #expect(mock.parameterizedAttributeCalls.count == 1)
        #expect(mock.parameterizedAttributeCalls.first?.attribute == kAXBoundsForRangeParameterizedAttribute)
    }

    @Test("boundsForRange returns nil when AX returns an error")
    func boundsForRangeReturnsNilOnError() throws {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)

        let text = "Hello"
        let suggestion = try #require(makeSuggestion(in: text, startChar: 0, endChar: 5))
        let element = AXUIElementCreateSystemWide()

        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.failure, nil)

        let result = controller.boundsForRange(suggestion, in: text, element: element)
        #expect(result == nil)
    }

    @Test("boundsForRange unpacks AXValue to CGRect")
    func boundsForRangeUnpacksRect() throws {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)

        let text = "Hello world"
        let suggestion = try #require(makeSuggestion(in: text, startChar: 0, endChar: 5))
        let element = AXUIElementCreateSystemWide()

        // Create AXValue containing a known CGRect
        var knownRect = CGRect(x: 100, y: 200, width: 50, height: 20)
        let axValue = AXValueCreate(.cgRect, &knownRect)!

        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValue)

        let result = controller.boundsForRange(suggestion, in: text, element: element)
        let rect = try #require(result)
        #expect(rect.origin.x == 100)
        #expect(rect.origin.y == 200)
        #expect(rect.width == 50)
        #expect(rect.height == 20)
    }

    @Test("boundsForRange passes correct CFRange (unicode scalar offsets) for ASCII text")
    func boundsForRangePassesCorrectCFRange() throws {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)

        let text = "Hello world"
        // "world" starts at scalar offset 6, ends at 11
        let suggestion = try #require(makeSuggestion(in: text, startChar: 6, endChar: 11))
        let element = AXUIElementCreateSystemWide()

        var knownRect = CGRect(x: 10, y: 20, width: 30, height: 15)
        let axValue = AXValueCreate(.cgRect, &knownRect)!
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValue)

        _ = controller.boundsForRange(suggestion, in: text, element: element)

        // Verify the CFRange parameter passed: location=6, length=5 (world)
        guard let call = mock.parameterizedAttributeCalls.first else {
            Issue.record("Expected one parameterized AX call")
            return
        }
        var cfRange = CFRange(location: 0, length: 0)
        let unpacked = AXValueGetValue(call.parameter as! AXValue, .cfRange, &cfRange)
        #expect(unpacked == true)
        #expect(cfRange.location == 6)
        #expect(cfRange.length == 5)
    }

    @Test("flipCGRect converts CG coordinates to AppKit coordinates")
    func flipCGRectConvertsCoordinates() {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)

        // CG: y=0 at bottom-left of screen
        // AppKit: y=0 at top-left of screen
        // For screenHeight=1000, cgRect.y=200, height=20:
        // AppKit y = 1000 - 200 - 20 = 780
        let cgRect = CGRect(x: 50, y: 200, width: 100, height: 20)
        let flipped = controller.flipCGRect(cgRect, screenHeight: 1000)

        #expect(flipped.origin.x == 50)
        #expect(flipped.origin.y == 780)
        #expect(flipped.width == 100)
        #expect(flipped.height == 20)
    }
}
