import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

// MARK: - Helpers

private func makeSuggestion(in text: String = "Hello world", startChar: Int = 0, endChar: Int = 5) -> Suggestion {
    let range = text.rangeFromCharOffsets(start: startChar, end: endChar) ?? text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: String(text[range]),
        primaryReplacement: "fixed",
        allReplacements: ["fixed"],
        message: "test issue",
        category: .spelling,
        source: .harper,
        priority: 1,
        paragraphHash: nil
    )
}

/// Returns an AXValue containing a CGRect, or nil if creation fails.
private func axValueFor(rect: CGRect) -> CFTypeRef? {
    var mutableRect = rect
    return AXValueCreate(.cgRect, &mutableRect)
}

// MARK: - Tests

@Suite("BoundsValidator validation")
struct BoundsValidatorTests {

    // Use a fresh watchdog per test to avoid shared-singleton busy-guard interference
    // when tests run in parallel.
    private func freshValidator() -> BoundsValidator {
        BoundsValidator(watchdog: AXCallWatchdog(hangThreshold: 5.0, blocklistDuration: 60.0))
    }

    @Test("rejectsZeroSizeBounds: width=0 height=0 returns nil")
    func rejectsZeroSizeBounds() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: 100, y: 100, width: 0, height: 0)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("rejectsTooSmallBounds: width=1 height=1 returns nil")
    func rejectsTooSmallBounds() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: 100, y: 100, width: 1, height: 1)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("rejectsTooLargeWidth: width=900 returns nil")
    func rejectsTooLargeWidth() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: 100, y: 100, width: 900, height: 20)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("rejectsTooLargeHeight: height=250 returns nil")
    func rejectsTooLargeHeight() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: 100, y: 100, width: 100, height: 250)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("rejectsNaNOrigin: NaN x-origin returns nil")
    func rejectsNaNOrigin() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: CGFloat.nan, y: 100, width: 50, height: 20)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("rejectsInfiniteOrigin: infinite x-origin returns nil")
    func rejectsInfiniteOrigin() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: CGFloat.infinity, y: 100, width: 50, height: 20)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }

    @Test("acceptsValidBounds: reasonable rect returns a non-nil array with one element")
    func acceptsValidBounds() {
        let mock = MockAXAccessor()
        let rect = CGRect(x: 200, y: 800, width: 80, height: 18)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result != nil)
        #expect(result?.count == 1)
    }

    @Test("flipsYCoordinateUsingPrimaryScreen: returned NSRect y-origin is screenHeight - cgY - height")
    func flipsYCoordinateUsingPrimaryScreen() throws {
        let mock = MockAXAccessor()
        let cgY: CGFloat = 800
        let height: CGFloat = 18
        let rect = CGRect(x: 200, y: cgY, width: 80, height: height)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValueFor(rect: rect))

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = try #require(validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock))
        #expect(result.count == 1)

        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
        let expectedY = screenHeight - cgY - height
        #expect(result[0].origin.y == expectedY)
    }

    @Test("AX error returns nil")
    func axErrorReturnsNil() {
        let mock = MockAXAccessor()
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.failure, nil)

        let validator = freshValidator()
        let suggestion = makeSuggestion()
        let element = AXUIElementCreateSystemWide()
        let result = validator.validatedBoundsForRange(suggestion, in: "Hello world", element: element, bundleID: "com.test.app", accessor: mock)
        #expect(result == nil)
    }
}
