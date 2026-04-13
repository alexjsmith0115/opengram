import Testing
import CoreGraphics
@testable import OpenGramLib

@Suite("HotkeyManager Tests")
struct HotkeyManagerTests {

    private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return event
    }

    // MARK: - isHotkey

    @Test("Ctrl+Shift+G fires hotkey")
    func isHotkey_ctrlShiftG_returnsTrue() {
        let manager = HotkeyManager()
        let event = makeKeyEvent(keyCode: 0x05, flags: [.maskControl, .maskShift])
        #expect(manager.isHotkey(event) == true)
    }

    @Test("Ctrl+G without Shift does not fire")
    func isHotkey_ctrlGOnly_returnsFalse() {
        let manager = HotkeyManager()
        let event = makeKeyEvent(keyCode: 0x05, flags: [.maskControl])
        #expect(manager.isHotkey(event) == false)
    }

    @Test("Ctrl+Shift+Cmd+G does not fire (extra modifier)")
    func isHotkey_ctrlShiftCmdG_returnsFalse() {
        let manager = HotkeyManager()
        let event = makeKeyEvent(keyCode: 0x05, flags: [.maskControl, .maskShift, .maskCommand])
        #expect(manager.isHotkey(event) == false)
    }

    @Test("Ctrl+Shift+A does not fire (wrong key)")
    func isHotkey_ctrlShiftA_returnsFalse() {
        let manager = HotkeyManager()
        let event = makeKeyEvent(keyCode: 0x00, flags: [.maskControl, .maskShift])
        #expect(manager.isHotkey(event) == false)
    }

    @Test("Ctrl+Shift+CapsLock+G fires (CapsLock ignored)")
    func isHotkey_ctrlShiftCapsG_returnsTrue() {
        let manager = HotkeyManager()
        let event = makeKeyEvent(keyCode: 0x05, flags: [.maskControl, .maskShift, .maskAlphaShift])
        #expect(manager.isHotkey(event) == true)
    }

    // MARK: - Install / Uninstall state management

    @Test("install and uninstall clears state")
    func installAndUninstall_clearsState() {
        let manager = HotkeyManager()
        manager.install()
        manager.uninstall()
        #expect(manager.eventTap == nil)
    }

    @Test("double install does not crash and uninstalls first")
    func doubleInstall_doesNotCrash() {
        let manager = HotkeyManager()
        manager.install()
        let firstTap = manager.eventTap
        manager.install()
        let secondTap = manager.eventTap
        if firstTap != nil {
            #expect(firstTap !== secondTap)
        }
        manager.uninstall()
    }
}
