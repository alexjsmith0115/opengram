import Testing
@testable import OpenGramLib

@Suite("AXCapabilities")
struct AXCapabilitiesTests {
    @Test("Default-constructed capabilities are all false")
    func defaults() {
        let caps = AXCapabilities()
        #expect(caps.canSetSelectedTextRange == false)
        #expect(caps.canSetSelectedText == false)
        #expect(caps.canReadSelectedText == false)
        #expect(caps.canSetValue == false)
        #expect(caps.canReadValue == false)
    }

    @Test("Memberwise init sets each bit independently")
    func memberwise() {
        let caps = AXCapabilities(
            canSetSelectedTextRange: true,
            canSetSelectedText: true,
            canReadSelectedText: false,
            canSetValue: true,
            canReadValue: true
        )
        #expect(caps.canSetSelectedTextRange)
        #expect(caps.canSetSelectedText)
        #expect(!caps.canReadSelectedText)
        #expect(caps.canSetValue)
        #expect(caps.canReadValue)
    }
}
