@preconcurrency import ApplicationServices
import AppKit

/// Serializes AX reads off the main actor. Actor isolation provides natural FIFO
/// ordering; awaits yield the main thread while reads block on target-app IPC.
///
/// All methods support cooperative cancellation via `Task.checkCancellation()`.
/// Callers wrap batches in a `Task` and cancel that task to abort remaining work.
actor AXCallQueue {
    private let accessor: any AXAccessor
    private let validator: BoundsValidator
    private let watchdog: AXCallWatchdog

    /// PERF-12: test-observable counter incremented on every `boundsBatch` call.
    /// Mirrors `OverlayController.applyBoundsCallCount` precedent — `internal` so
    /// `@testable` tests can `await queue.boundsBatchCallCount` to assert the
    /// zero-AX accept path.
    var boundsBatchCallCount: Int = 0

    init(
        accessor: any AXAccessor = SystemAXAccessor(),
        validator: BoundsValidator = BoundsValidator(),
        watchdog: AXCallWatchdog = .shared
    ) {
        self.accessor = accessor
        self.validator = validator
        self.watchdog = watchdog
    }

    /// Single-suggestion bounds query. Throws CancellationError if the enclosing
    /// Task was cancelled before the AX call is dispatched.
    func bounds(
        for suggestion: Suggestion,
        in text: String,
        element: AXUIElement,
        bundleID: String
    ) async throws -> [NSRect]? {
        try Task.checkCancellation()
        return validator.validatedBoundsForRange(
            suggestion, in: text, element: element,
            bundleID: bundleID, accessor: accessor
        )
    }

    /// Batch variant. Yields between suggestions so long batches don't starve
    /// other actor work, and checks cancellation between each. Preserves input
    /// order; skips suggestions that fail validation.
    func boundsBatch(
        suggestions: [Suggestion],
        in text: String,
        element: AXUIElement,
        bundleID: String
    ) async throws -> [(suggestion: Suggestion, rects: [NSRect])] {
        boundsBatchCallCount += 1
        var results: [(suggestion: Suggestion, rects: [NSRect])] = []
        results.reserveCapacity(suggestions.count)
        for suggestion in suggestions {
            try Task.checkCancellation()
            if let rects = validator.validatedBoundsForRange(
                suggestion, in: text, element: element,
                bundleID: bundleID, accessor: accessor
            ) {
                results.append((suggestion, rects))
            }
            await Task.yield()
        }
        return results
    }

    /// Element-level attribute read. Wraps the two raw AX reads with the
    /// watchdog so hang detection + per-app blocklist still cover this path
    /// (D-06). Returns nil when the app is blocklisted or either read fails.
    func elementBounds(_ element: AXUIElement, bundleID: String) async throws -> CGRect? {
        try Task.checkCancellation()
        guard !watchdog.shouldSkip(for: bundleID) else { return nil }

        watchdog.beginCall(bundleID: bundleID, attribute: kAXPositionAttribute)
        let (posErr, posRef) = accessor.copyAttributeValue(element, kAXPositionAttribute)
        watchdog.endCall()

        try Task.checkCancellation()

        watchdog.beginCall(bundleID: bundleID, attribute: kAXSizeAttribute)
        let (sizeErr, sizeRef) = accessor.copyAttributeValue(element, kAXSizeAttribute)
        watchdog.endCall()

        guard posErr == .success, sizeErr == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}
