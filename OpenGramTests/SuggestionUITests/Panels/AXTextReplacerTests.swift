import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

@MainActor
@Suite("AXTextReplacer")
struct AXTextReplacerTests {

    @Test func rangeWrite_succeeds_whenBothSetsSucceed() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let range = CFRange(location: 0, length: 3)
        let ok = replacer.replace(strategy: .rangeAndSelectedText(range), replacement: "new", element: dummy)
        #expect(ok == true)
        #expect(mock.setAttributeCalls.count == 2)   // range + text
    }

    @Test func rangeWrite_returnsFalse_whenSetRangeFails() {
        let mock = MockAXAccessor()
        // First set (range) fails
        mock.setAttributeResultsByCall = { idx in idx == 0 ? .failure : .success }
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let range = CFRange(location: 0, length: 5)
        let ok = replacer.replace(strategy: .rangeAndSelectedText(range), replacement: "HELLO", element: dummy)
        #expect(ok == false)
    }

    @Test func valueSplice_fails_whenReadFails() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        let range = CFRange(location: 0, length: 0)
        let ok = replacer.replace(strategy: .valueSplice(range), replacement: "x", element: dummy)
        #expect(ok == false)
    }

    @Test func valueSplice_splicesCorrectly() {
        let mock = MockAXAccessor()
        mock.attributeValues[kAXValueAttribute] = (.success, "hello world" as CFString)
        mock.setAttributeResult = .success
        let replacer = AXTextReplacer(accessor: mock)
        let dummy = AXUIElementCreateSystemWide()
        // "world" is UTF-16 indices 6..11
        let range = CFRange(location: 6, length: 5)
        let ok = replacer.replace(strategy: .valueSplice(range), replacement: "WORLD", element: dummy)
        #expect(ok == true)
        let lastWrite = mock.setAttributeCalls.last!
        #expect((lastWrite.value as? String) == "hello WORLD")
    }
}
