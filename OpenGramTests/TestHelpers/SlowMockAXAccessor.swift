import Foundation
@preconcurrency import ApplicationServices

@testable import OpenGramLib

/// AXAccessor wrapper that sleeps synchronously for an injected `Duration`
/// on every protocol call, then delegates to a wrapped `MockAXAccessor`.
///
/// Purpose: open a deterministic cancellation window for PERF-03 tests.
/// `AXCallQueue.boundsBatch` calls `accessor.copyParameterizedAttributeValue`
/// synchronously between `try Task.checkCancellation()` + `await Task.yield()`;
/// a synchronous per-call sleep guarantees the second `scheduleReposition`
/// can cancel the first before the first completes its batch.
///
/// `MockAXAccessor` is `final` (cannot subclass). Wrap + delegate is equivalent
/// for test purposes and keeps the passthrough explicit.
final class SlowMockAXAccessor: AXAccessor, @unchecked Sendable {
    let wrapped: MockAXAccessor
    let delay: Duration

    init(delay: Duration, wrapped: MockAXAccessor = MockAXAccessor()) {
        self.delay = delay
        self.wrapped = wrapped
    }

    /// Convenience passthroughs so tests can configure the wrapped mock directly
    /// via `slow.parameterizedAttributeValues[...] = ...` without reaching into
    /// `slow.wrapped`.
    var parameterizedAttributeValues: [String: (AXError, CFTypeRef?)] {
        get { wrapped.parameterizedAttributeValues }
        set { wrapped.parameterizedAttributeValues = newValue }
    }

    var attributeValues: [String: (AXError, CFTypeRef?)] {
        get { wrapped.attributeValues }
        set { wrapped.attributeValues = newValue }
    }

    // MARK: - AXAccessor conformance

    func copyAttributeValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, CFTypeRef?) {
        sleep()
        return wrapped.copyAttributeValue(element, attribute)
    }

    func isAttributeSettable(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, Bool) {
        sleep()
        return wrapped.isAttributeSettable(element, attribute)
    }

    func setAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ value: CFTypeRef
    ) -> AXError {
        sleep()
        return wrapped.setAttributeValue(element, attribute, value)
    }

    func copyParameterizedAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ parameter: CFTypeRef
    ) -> (AXError, CFTypeRef?) {
        sleep()
        return wrapped.copyParameterizedAttributeValue(element, attribute, parameter)
    }

    func isProcessTrusted() -> Bool { wrapped.isProcessTrusted() }
    func systemWideElement() -> AXUIElement { wrapped.systemWideElement() }
    func frontmostBundleID() -> String? { wrapped.frontmostBundleID() }
    func frontmostBundleVersion() -> String? { wrapped.frontmostBundleVersion() }

    // MARK: - Internal

    private func sleep() {
        // Synchronous sleep — AX protocol methods are sync. The enclosing
        // AXCallQueue.boundsBatch yields the actor between items, so this
        // blocks only the current item, not the main thread.
        let seconds = Double(delay.components.seconds) +
                      Double(delay.components.attoseconds) / 1e18
        Thread.sleep(forTimeInterval: seconds)
    }
}
