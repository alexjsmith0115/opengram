import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

// MARK: - Helpers (inlined per D-10; AXTextEngineTests.MockAXAccessor reused via @testable import)

private func makeSuggestion(
    id: UUID = UUID(),
    original: String = "recieve",
    primaryReplacement: String = "receive"
) -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: id,
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

private func makeAXRectValue(_ rect: CGRect = CGRect(x: 100, y: 200, width: 50, height: 14)) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

@Suite("AXCallQueue")
struct AXCallQueueTests {

    @Test("boundsBatch returns one entry per suggestion when validator succeeds")
    func boundsBatchSuccess() async throws {
        let mock = MockAXAccessor()
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, makeAXRectValue(CGRect(x: 0, y: 0, width: 100, height: 20)))

        let queue = AXCallQueue(accessor: mock)
        let suggestions = [makeSuggestion(), makeSuggestion()]
        let results = try await queue.boundsBatch(
            suggestions: suggestions, in: "hello world",
            element: AXUIElementCreateSystemWide(), bundleID: "com.test"
        )
        #expect(results.count == 2)
    }

    @Test("boundsBatch throws CancellationError when enclosing task is cancelled")
    func boundsBatchCancellation() async throws {
        let mock = MockAXAccessor()
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
            (.success, makeAXRectValue(CGRect(x: 0, y: 0, width: 100, height: 20)))

        let queue = AXCallQueue(accessor: mock)
        // Large batch so cancellation can propagate before completion.
        let suggestions = (0..<1000).map { _ in makeSuggestion() }

        let task = Task { () -> Bool in
            do {
                _ = try await queue.boundsBatch(
                    suggestions: suggestions, in: "hello world",
                    element: AXUIElementCreateSystemWide(), bundleID: "com.test"
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        task.cancel()
        let cancelled = await task.value
        #expect(cancelled)
    }

    @Test("elementBounds returns combined rect on success")
    func elementBoundsSuccess() async throws {
        let mock = MockAXAccessor()
        var point = CGPoint(x: 10, y: 20)
        var size = CGSize(width: 400, height: 300)
        mock.attributeValues[kAXPositionAttribute] =
            (.success, AXValueCreate(.cgPoint, &point))
        mock.attributeValues[kAXSizeAttribute] =
            (.success, AXValueCreate(.cgSize, &size))

        let queue = AXCallQueue(accessor: mock)
        let rect = try await queue.elementBounds(
            AXUIElementCreateSystemWide(),
            bundleID: "com.test.success"
        )
        #expect(rect == CGRect(x: 10, y: 20, width: 400, height: 300))
    }

    @Test("elementBounds returns nil when AX read fails")
    func elementBoundsFailure() async throws {
        let mock = MockAXAccessor()  // no values registered → .attributeUnsupported fallback
        let queue = AXCallQueue(accessor: mock)
        let result = try await queue.elementBounds(
            AXUIElementCreateSystemWide(),
            bundleID: "com.test.failure"
        )
        #expect(result == nil)
    }
}
