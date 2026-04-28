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

@Suite("HotkeyManager dispatch")
@MainActor
struct HotkeyManagerDispatchTests {
    @Test("Detects Ctrl+Shift+G as .check")
    func detectsCheckHotkey() {
        let manager = HotkeyManager()
        #expect(manager.detectHotkey(keyCode: 0x05, // kVK_ANSI_G
                                     flags: [.maskControl, .maskShift]) == .check)
    }

    @Test("Detects Ctrl+Shift+R as .rewrite")
    func detectsRewriteHotkey() {
        let manager = HotkeyManager()
        #expect(manager.detectHotkey(keyCode: 0x0F, // kVK_ANSI_R
                                     flags: [.maskControl, .maskShift]) == .rewrite)
    }

    @Test("Returns nil for non-matching keycode")
    func ignoresOtherKeys() {
        let manager = HotkeyManager()
        #expect(manager.detectHotkey(keyCode: 0x00, // kVK_ANSI_A
                                     flags: [.maskControl, .maskShift]) == nil)
    }

    @Test("Requires both Control and Shift")
    func requiresBothModifiers() {
        let manager = HotkeyManager()
        #expect(manager.detectHotkey(keyCode: 0x0F, flags: [.maskControl]) == nil)
        #expect(manager.detectHotkey(keyCode: 0x0F, flags: [.maskShift]) == nil)
    }
}
