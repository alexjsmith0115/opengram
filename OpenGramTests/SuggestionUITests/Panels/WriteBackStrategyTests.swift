import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

@Suite("WriteBackStrategy.choose")
struct WriteBackStrategyChooserTests {
    private let range = CFRange(location: 0, length: 5)

    @Test("Range present + range+selectedText caps -> rangeAndSelectedText")
    func rangeAndSelectedText() {
        let caps = AXCapabilities(canSetSelectedTextRange: true,
                                  canSetSelectedText: true,
                                  canReadSelectedText: true,
                                  canSetValue: true,
                                  canReadValue: true)
        let strategy = WriteBackStrategy.choose(range: range, caps: caps)
        guard case .rangeAndSelectedText(let r) = strategy else {
            Issue.record("Expected .rangeAndSelectedText, got \(String(describing: strategy))"); return
        }
        #expect(r.location == range.location && r.length == range.length)
    }

    @Test("Range present, only value bits -> valueSplice")
    func valueSplice() {
        let caps = AXCapabilities(canSetSelectedTextRange: false,
                                  canSetSelectedText: false,
                                  canReadSelectedText: false,
                                  canSetValue: true,
                                  canReadValue: true)
        let strategy = WriteBackStrategy.choose(range: range, caps: caps)
        guard case .valueSplice = strategy else {
            Issue.record("Expected .valueSplice"); return
        }
    }

    @Test("Range present, no caps -> nil")
    func rangeButNoCaps() {
        let caps = AXCapabilities()
        #expect(WriteBackStrategy.choose(range: range, caps: caps) == nil)
    }

    @Test("Nil range, selected-text bits -> selectedTextOnly")
    func selectedTextOnly() {
        let caps = AXCapabilities(canSetSelectedText: true, canReadSelectedText: true)
        #expect(WriteBackStrategy.choose(range: nil, caps: caps) == .selectedTextOnly)
    }

    @Test("Nil range, missing read OR write -> nil")
    func nilRangeMissingBits() {
        var caps = AXCapabilities(canSetSelectedText: true, canReadSelectedText: false)
        #expect(WriteBackStrategy.choose(range: nil, caps: caps) == nil)
        caps = AXCapabilities(canSetSelectedText: false, canReadSelectedText: true)
        #expect(WriteBackStrategy.choose(range: nil, caps: caps) == nil)
    }
}
