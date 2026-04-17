import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

@MainActor
@Suite("AXTextReplacer")
struct AXTextReplacerTests {

    @Test func rangeWrite_succeeds_whenSettableAndBothSetsSucceed() {
        let mock = MockAXAccessor()
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.setAttributeResult = .success
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let ok = replacer.replace(text: "new", in: (scalarStart: 0, scalarLength: 3), of: dummy)
        #expect(ok == true)
        #expect(mock.setAttributeCalls.count == 2)   // range + text
    }

    @Test func rangeWrite_fallsBackToFull_whenSetRangeFails() {
        let mock = MockAXAccessor()
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // First set (range) fails, second (full-text write) succeeds
        mock.setAttributeResultsByCall = { idx in idx == 0 ? .failure : .success }
        mock.attributeValues[kAXValueAttribute] = (.success, "hello world" as CFString)
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let ok = replacer.replace(text: "HELLO", in: (scalarStart: 0, scalarLength: 5), of: dummy)
        #expect(ok == true)
    }

    @Test func fullFallback_fails_whenReadFails() {
        let mock = MockAXAccessor()
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let ok = replacer.replace(text: "x", in: (scalarStart: 0, scalarLength: 0), of: dummy)
        #expect(ok == false)
    }

    @Test func fullFallback_splicesCorrectly() {
        let mock = MockAXAccessor()
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.success, "hello world" as CFString)
        mock.setAttributeResult = .success
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let ok = replacer.replace(text: "WORLD", in: (scalarStart: 6, scalarLength: 5), of: dummy)
        #expect(ok == true)
        let lastWrite = mock.setAttributeCalls.last!
        #expect((lastWrite.value as? String) == "hello WORLD")
    }
}
