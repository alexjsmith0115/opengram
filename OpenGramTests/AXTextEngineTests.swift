import Testing
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

/// Mock AXAccessor that returns controlled values for unit testing.
final class MockAXAccessor: AXAccessor, @unchecked Sendable {
    var processIsTrusted = true
    var bundleID: String? = "com.test.app"
    var bundleVersion: String? = "1.0"

    /// Maps (attribute name) -> (error, value) for copyAttributeValue calls.
    /// The element parameter is ignored since tests use a single dummy element.
    var attributeValues: [String: (AXError, CFTypeRef?)] = [:]

    /// Maps (attribute name) -> (error, settable) for isAttributeSettable calls.
    var attributeSettable: [String: (AXError, Bool)] = [:]

    /// Records setAttributeValue calls for verification.
    var setAttributeCalls: [(attribute: String, value: CFTypeRef)] = []
    var setAttributeResult: AXError = .success

    /// Per-call override: if set, invoked with the call index and its return value overrides setAttributeResult.
    var setAttributeResultsByCall: ((Int) -> AXError)?

    /// Maps (attribute name) -> (error, value) for copyParameterizedAttributeValue calls.
    var parameterizedAttributeValues: [String: (AXError, CFTypeRef?)] = [:]

    /// Records copyParameterizedAttributeValue calls for verification.
    var parameterizedAttributeCalls: [(attribute: String, parameter: CFTypeRef)] = []

    private let dummySystemWide = AXUIElementCreateSystemWide()

    func copyAttributeValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, CFTypeRef?) {
        if let entry = attributeValues[attribute] {
            return entry
        }
        return (.attributeUnsupported, nil)
    }

    func isAttributeSettable(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, Bool) {
        if let entry = attributeSettable[attribute] {
            return entry
        }
        return (.attributeUnsupported, false)
    }

    func setAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ value: CFTypeRef
    ) -> AXError {
        let callIndex = setAttributeCalls.count
        setAttributeCalls.append((attribute: attribute, value: value))
        if let override = setAttributeResultsByCall {
            return override(callIndex)
        }
        return setAttributeResult
    }

    func copyParameterizedAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ parameter: CFTypeRef
    ) -> (AXError, CFTypeRef?) {
        parameterizedAttributeCalls.append((attribute: attribute, parameter: parameter))
        if let entry = parameterizedAttributeValues[attribute] {
            return entry
        }
        return (.parameterizedAttributeUnsupported, nil)
    }

    func isProcessTrusted() -> Bool { processIsTrusted }
    func systemWideElement() -> AXUIElement { dummySystemWide }
    func frontmostBundleID() -> String? { bundleID }
    func frontmostBundleVersion() -> String? { bundleVersion }
}

/// Stub capability cache that records calls without disk I/O.
final class StubCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
    private var entries: [String: Bool] = [:]
    private var notificationEntries: [String: Bool] = [:]
    var storeCalls: [(bundleID: String, version: String?, supported: Bool)] = []

    func isSupported(bundleID: String, version: String?) -> Bool? {
        let key = bundleID + ":" + (version ?? "unknown")
        return entries[key]
    }

    func store(bundleID: String, version: String?, supported: Bool) {
        let key = bundleID + ":" + (version ?? "unknown")
        entries[key] = supported
        storeCalls.append((bundleID: bundleID, version: version, supported: supported))
    }

    func isNotificationReliable(bundleID: String) -> Bool? {
        notificationEntries[bundleID]
    }

    func storeNotificationReliability(bundleID: String, reliable: Bool) {
        notificationEntries[bundleID] = reliable
    }

    func separator(bundleID: String, version: String?) -> String? { nil }
    func storeSeparator(bundleID: String, version: String?, separator: String) {}

    func preload(bundleID: String, version: String?, supported: Bool) {
        let key = bundleID + ":" + (version ?? "unknown")
        entries[key] = supported
    }
}

@Suite("AXTextEngine text extraction")
struct AXTextEngineExtractTests {
    let dummyElement = AXUIElementCreateSystemWide()

    private func makeEngine(
        mock: MockAXAccessor = MockAXAccessor(),
        cache: StubCapabilityCache = StubCapabilityCache()
    ) -> AXTextEngine {
        AXTextEngine(accessor: mock, capabilityCache: cache)
    }

    @Test("extractText returns .axDirectSelection when selected text is non-empty")
    @MainActor func extractSelectedText() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()

        mock.attributeValues[kAXFocusedUIElementAttribute] = (.success, dummyElement)
        mock.attributeValues[kAXValueAttribute] = (.success, "Full text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, true)
        mock.attributeValues[kAXSelectedTextAttribute] = (.success, "selected" as CFString)
        mock.attributeValues[kAXSelectedTextRangeAttribute] = (.attributeUnsupported, nil)
        mock.attributeValues[kAXPositionAttribute] = (.attributeUnsupported, nil)

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context != nil)
        #expect(context?.text == "selected")
        #expect(context?.extractionMethod == .axDirectSelection)
        #expect(context?.bundleID == "com.test.app")
    }

    @Test("extractText returns .axDirectFull when selected text is empty but full value exists")
    @MainActor func extractFullValue() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()

        mock.attributeValues[kAXFocusedUIElementAttribute] = (.success, dummyElement)
        mock.attributeValues[kAXValueAttribute] = (.success, "Full field text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, true)
        mock.attributeValues[kAXSelectedTextAttribute] = (.success, "" as CFString)
        mock.attributeValues[kAXSelectedTextRangeAttribute] = (.attributeUnsupported, nil)
        mock.attributeValues[kAXPositionAttribute] = (.attributeUnsupported, nil)

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context != nil)
        #expect(context?.text == "Full field text")
        #expect(context?.extractionMethod == .axDirectFull)
    }

    @Test("extractText returns nil when both selected text and full value are empty")
    @MainActor func extractNilWhenBothEmpty() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()

        mock.attributeValues[kAXFocusedUIElementAttribute] = (.success, dummyElement)
        mock.attributeValues[kAXValueAttribute] = (.success, "" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, true)
        mock.attributeValues[kAXSelectedTextAttribute] = (.success, "" as CFString)

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context == nil)
    }

    @Test("extractText returns nil when AXIsProcessTrusted is false")
    @MainActor func extractNilWhenNotTrusted() {
        let mock = MockAXAccessor()
        mock.processIsTrusted = false
        let cache = StubCapabilityCache()

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context == nil)
    }

    @Test("extractText returns nil when capability probe fails (read-only element)")
    @MainActor func extractNilWhenProbeFailsReadOnly() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()

        mock.attributeValues[kAXFocusedUIElementAttribute] = (.success, dummyElement)
        mock.attributeValues[kAXValueAttribute] = (.success, "some text" as CFString)
        // Write check fails: element is read-only
        mock.attributeSettable[kAXValueAttribute] = (.success, false)

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context == nil)
        #expect(cache.storeCalls.count == 1)
        #expect(cache.storeCalls.first?.supported == false)
    }

    @Test("extractText bypasses stale unsupported cache for Outlook")
    @MainActor func extractBypassesCachedUnsupportedForOutlook() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.bundleID = "com.microsoft.Outlook"
        mock.bundleVersion = "16.108"
        cache.preload(bundleID: "com.microsoft.Outlook", version: "16.108", supported: false)

        mock.attributeValues[kAXFocusedUIElementAttribute] = (.success, dummyElement)
        mock.attributeValues[kAXValueAttribute] = (.success, "Outlook body text" as CFString)
        mock.attributeValues[kAXSelectedTextAttribute] = (.success, "" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, false)
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.attributeValues[kAXSelectedTextRangeAttribute] = (.attributeUnsupported, nil)
        mock.attributeValues[kAXPositionAttribute] = (.attributeUnsupported, nil)

        let engine = makeEngine(mock: mock, cache: cache)
        let context = engine.extractText()

        #expect(context?.text == "Outlook body text")
        #expect(cache.storeCalls.last?.supported == true)
    }
}

@Suite("AXTextEngine capability probe")
struct AXTextEngineProbeTests {
    let dummyElement = AXUIElementCreateSystemWide()

    @Test("probeCapability returns true when element is settable")
    @MainActor func probeReturnsTrue() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.attributeValues[kAXValueAttribute] = (.success, "text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, true)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let result = engine.probeCapability(element: dummyElement)

        #expect(result == true)
    }

    @Test("probeCapability returns true when selected text range is settable")
    @MainActor func probeReturnsTrueForRangeWritableRichEditor() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.attributeValues[kAXValueAttribute] = (.success, "text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, false)
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let result = engine.probeCapability(element: dummyElement)

        #expect(result == true)
    }

    @Test("probeCapability returns true when selected text replacement is settable")
    @MainActor func probeReturnsTrueForSelectedTextWritableRichEditor() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.attributeValues[kAXValueAttribute] = (.success, "text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, false)
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeSettable[kAXSelectedTextAttribute] = (.success, true)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let result = engine.probeCapability(element: dummyElement)

        #expect(result == true)
    }

    @Test("probeCapability returns false when element is not settable (read-only)")
    @MainActor func probeReturnsFalseReadOnly() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.attributeValues[kAXValueAttribute] = (.success, "text" as CFString)
        mock.attributeSettable[kAXValueAttribute] = (.success, false)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let result = engine.probeCapability(element: dummyElement)

        #expect(result == false)
    }

    @Test("probeCapability returns false when read fails entirely")
    @MainActor func probeReturnsFalseNoValue() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let result = engine.probeCapability(element: dummyElement)

        #expect(result == false)
    }
}

@Suite("AXTextEngine write-back")
struct AXTextEngineWriteBackTests {
    let dummyElement = AXUIElementCreateSystemWide()

    @Test("writeBack returns false when element is stale (Pitfall 5)")
    @MainActor func writeBackFailsOnStaleElement() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        // Stale element: read check fails
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let context = TextContext(
            text: "original",
            bundleID: "com.test.app",
            extractionMethod: .axDirectSelection,
            selectionRange: CFRange(location: 0, length: 8),
            elementBounds: nil,
            capabilities: AXCapabilities(),
            axElement: dummyElement
        )

        let result = engine.writeBack(context: context, replacement: "fixed")

        #expect(result == false)
        #expect(mock.setAttributeCalls.isEmpty)
    }

    @Test("writeBack uses kAXSelectedTextAttribute for replacement (not kAXValueAttribute)")
    @MainActor func writeBackUsesSelectedText() {
        let mock = MockAXAccessor()
        let cache = StubCapabilityCache()
        // Valid element
        mock.attributeValues[kAXValueAttribute] = (.success, "original text" as CFString)

        let engine = AXTextEngine(accessor: mock, capabilityCache: cache)
        let context = TextContext(
            text: "original",
            bundleID: "com.test.app",
            extractionMethod: .axDirectSelection,
            selectionRange: CFRange(location: 0, length: 8),
            elementBounds: nil,
            capabilities: AXCapabilities(),
            axElement: dummyElement
        )

        let result = engine.writeBack(context: context, replacement: "corrected")

        #expect(result == true)

        let selectedTextWrites = mock.setAttributeCalls.filter {
            $0.attribute == kAXSelectedTextAttribute
        }
        #expect(selectedTextWrites.count == 1)

        let valueWrites = mock.setAttributeCalls.filter {
            $0.attribute == kAXValueAttribute
        }
        #expect(valueWrites.isEmpty)
    }
}

@Suite("AXTextEngine.readLiveText / readLiveSelectedText")
struct AXTextEngineLiveReadTests {
    let dummyElement = AXUIElementCreateSystemWide()

    private func makeEngine(mock: MockAXAccessor) -> AXTextEngine {
        AXTextEngine(accessor: mock, capabilityCache: StubCapabilityCache())
    }

    @Test("readLiveText returns substring at range from kAXValueAttribute")
    @MainActor func readLiveText_returnsSubstring() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXValueAttribute] = (.success, "the quick brown fox" as CFString)
        let engine = makeEngine(mock: mock)
        let result = engine.readLiveText(at: CFRange(location: 4, length: 5), of: dummyElement)
        #expect(result == "quick")
    }

    @Test("readLiveText returns nil when AX read fails")
    @MainActor func readLiveText_returnsNilOnError() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)
        let engine = makeEngine(mock: mock)
        let result = engine.readLiveText(at: CFRange(location: 0, length: 3), of: dummyElement)
        #expect(result == nil)
    }

    @Test("readLiveSelectedText returns selected text from kAXSelectedTextAttribute")
    @MainActor func readLiveSelectedText_returnsText() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXSelectedTextAttribute] = (.success, "hello" as CFString)
        let engine = makeEngine(mock: mock)
        let result = engine.readLiveSelectedText(of: dummyElement)
        #expect(result == "hello")
    }

    @Test("readLiveSelectedText returns nil on AX error")
    @MainActor func readLiveSelectedText_returnsNilOnError() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXSelectedTextAttribute] = (.failure, nil)
        let engine = makeEngine(mock: mock)
        let result = engine.readLiveSelectedText(of: dummyElement)
        #expect(result == nil)
    }
}
