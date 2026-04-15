import Testing
import AppKit
@testable import OpenGramLib

@Suite("MenuBuilder")
struct MenuBuilderTests {

    @Test("Built menu has exactly 4 items including separator")
    func menuItemCount() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        #expect(menu.items.count == 4)
    }

    @Test("First item is disabled status line")
    func statusLineDisabled() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        let statusItem = menu.items[0]
        #expect(!statusItem.isEnabled)
        #expect(statusItem.action == nil)
    }

    @Test("First item title is 'OpenGram: Ready' by default")
    func statusLineDefaultTitle() {
        let builder = MenuBuilder()
        _ = builder.buildMenu()
        #expect(builder.statusMenuItem.title == "OpenGram: Ready")
    }

    @Test("updateStatusText changes the first item title")
    func updateStatusText() {
        let builder = MenuBuilder()
        _ = builder.buildMenu()
        builder.updateStatusText("OpenGram: Checking...")
        #expect(builder.statusMenuItem.title == "OpenGram: Checking...")
    }

    @Test("Settings item has correct title")
    func settingsItemTitle() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        let settingsItem = menu.items[1]
        #expect(settingsItem.title == "Settings\u{2026}")
    }

    @Test("Third item is a separator")
    func separatorItem() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        #expect(menu.items[2].isSeparatorItem)
    }

    @Test("Quit item has correct title")
    func quitItemTitle() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        let quitItem = menu.items[3]
        #expect(quitItem.title == "Quit OpenGram")
    }

    @Test("Quit item has keyEquivalent 'q'")
    func quitKeyEquivalent() {
        let builder = MenuBuilder()
        let menu = builder.buildMenu()
        let quitItem = menu.items[3]
        #expect(quitItem.keyEquivalent == "q")
    }
}
