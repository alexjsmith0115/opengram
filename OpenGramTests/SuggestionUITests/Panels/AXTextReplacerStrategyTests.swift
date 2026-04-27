import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

/// Recording AXAccessor for verifying which attributes are read/written and in what order.
final class RecordingAXAccessor: AXAccessor, @unchecked Sendable {
    /// (attribute, value) pairs in call order.
    var setCalls: [(attribute: String, value: AnyObject)] = []
    /// Per-attribute AX error to return for setAttributeValue. Defaults to .success.
    var setErrors: [String: AXError] = [:]
    /// Per-attribute AX error to return for copyAttributeValue. Defaults to .attributeUnsupported.
    var copyErrors: [String: AXError] = [:]
    /// Per-attribute value to return for copyAttributeValue.
    var values: [String: AnyObject] = [:]

    private let dummySystemWide = AXUIElementCreateSystemWide()

    func copyAttributeValue(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        let err = copyErrors[attribute] ?? .attributeUnsupported
        let val = values[attribute]
        return (err, val)
    }

    func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> (AXError, Bool) {
        (.success, true)
    }

    func setAttributeValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        setCalls.append((attribute: attribute, value: value))
        return setErrors[attribute] ?? .success
    }

    func copyParameterizedAttributeValue(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> (AXError, CFTypeRef?) {
        (.parameterizedAttributeUnsupported, nil)
    }

    func isProcessTrusted() -> Bool { true }
    func systemWideElement() -> AXUIElement { dummySystemWide }
    func frontmostBundleID() -> String? { "com.test.app" }
    func frontmostBundleVersion() -> String? { "1.0" }
}

@MainActor
@Suite("AXTextReplacer strategy dispatch")
struct AXTextReplacerStrategyTests {
    let dummy = AXUIElementCreateSystemWide()

    @Test(".rangeAndSelectedText happy path — sets range then selected text")
    func rangeAndSelectedText_happyPath() {
        let rec = RecordingAXAccessor()
        let replacer = AXTextReplacer(accessor: rec)
        let range = CFRange(location: 2, length: 4)
        let ok = replacer.replace(strategy: .rangeAndSelectedText(range), replacement: "done", element: dummy)
        #expect(ok == true)
        #expect(rec.setCalls.count == 2)
        #expect(rec.setCalls[0].attribute == kAXSelectedTextRangeAttribute)
        #expect(rec.setCalls[1].attribute == kAXSelectedTextAttribute)
        #expect((rec.setCalls[1].value as? String) == "done")
    }

    @Test(".rangeAndSelectedText returns false when range set fails")
    func rangeAndSelectedText_failsOnRangeError() {
        let rec = RecordingAXAccessor()
        rec.setErrors[kAXSelectedTextRangeAttribute] = .failure
        let replacer = AXTextReplacer(accessor: rec)
        let range = CFRange(location: 0, length: 3)
        let ok = replacer.replace(strategy: .rangeAndSelectedText(range), replacement: "x", element: dummy)
        #expect(ok == false)
        // Only the range set should have been attempted; no selected-text set.
        #expect(rec.setCalls.count == 1)
        #expect(rec.setCalls[0].attribute == kAXSelectedTextRangeAttribute)
    }

    @Test(".valueSplice happy path — reads value, splices, writes back")
    func valueSplice_happyPath() {
        let rec = RecordingAXAccessor()
        rec.copyErrors[kAXValueAttribute] = .success
        rec.values[kAXValueAttribute] = "hello world" as AnyObject
        let replacer = AXTextReplacer(accessor: rec)
        // Replace "world" (UTF-16 indices 6..11)
        let range = CFRange(location: 6, length: 5)
        let ok = replacer.replace(strategy: .valueSplice(range), replacement: "WORLD", element: dummy)
        #expect(ok == true)
        #expect(rec.setCalls.count == 1)
        #expect(rec.setCalls[0].attribute == kAXValueAttribute)
        #expect((rec.setCalls[0].value as? String) == "hello WORLD")
    }

    @Test(".valueSplice returns false when read fails")
    func valueSplice_failsOnReadError() {
        let rec = RecordingAXAccessor()
        rec.copyErrors[kAXValueAttribute] = .failure
        let replacer = AXTextReplacer(accessor: rec)
        let range = CFRange(location: 0, length: 5)
        let ok = replacer.replace(strategy: .valueSplice(range), replacement: "x", element: dummy)
        #expect(ok == false)
        #expect(rec.setCalls.isEmpty)
    }

    @Test(".selectedTextOnly sets kAXSelectedTextAttribute only")
    func selectedTextOnly_setsOnlySelectedText() {
        let rec = RecordingAXAccessor()
        let replacer = AXTextReplacer(accessor: rec)
        let ok = replacer.replace(strategy: .selectedTextOnly, replacement: "fixed", element: dummy)
        #expect(ok == true)
        #expect(rec.setCalls.count == 1)
        #expect(rec.setCalls[0].attribute == kAXSelectedTextAttribute)
        #expect((rec.setCalls[0].value as? String) == "fixed")
    }
}
