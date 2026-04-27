import Testing
@testable import OpenGramLib

@Suite("HotkeyAction")
struct HotkeyActionTests {
    @Test("HotkeyAction has check and rewrite as distinct cases")
    func cases() {
        let actions: [HotkeyAction] = [.check, .rewrite]
        #expect(actions.count == 2)
        #expect(HotkeyAction.check != HotkeyAction.rewrite)
    }
}
