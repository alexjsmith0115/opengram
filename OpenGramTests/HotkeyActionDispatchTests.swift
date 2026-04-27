import Testing
@testable import OpenGramLib

@Suite("HotkeyAction")
struct HotkeyActionTests {
    @Test("HotkeyAction has check and rewrite cases")
    func cases() {
        let actions: [HotkeyAction] = [.check, .rewrite]
        #expect(actions.count == 2)
    }
}
