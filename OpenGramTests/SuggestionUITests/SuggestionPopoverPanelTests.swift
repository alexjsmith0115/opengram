import Testing
import AppKit

@testable import OpenGramLib

@Suite("SuggestionPopoverPanel window properties")
@MainActor
struct SuggestionPopoverPanelTests {

    @Test("canBecomeKey returns false")
    func canBecomeKeyIsFalse() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.canBecomeKey == false)
    }

    @Test("isFloatingPanel is true")
    func isFloatingPanelIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.isFloatingPanel == true)
    }

    @Test("level is popUpMenu")
    func levelIsPopUpMenu() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.level == .popUpMenu)
    }

    @Test("styleMask includes nonactivatingPanel")
    func styleMaskIncludesNonactivatingPanel() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    @Test("styleMask does not include hudWindow")
    func styleMaskExcludesHudWindow() {
        let panel = SuggestionPopoverPanel()
        #expect(!panel.styleMask.contains(.hudWindow))
    }

    @Test("becomesKeyOnlyIfNeeded is true")
    func becomesKeyOnlyIfNeededIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.becomesKeyOnlyIfNeeded == true)
    }

    @Test("backgroundColor is clear")
    func backgroundColorIsClear() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.backgroundColor == .clear)
    }

    @Test("hasShadow is true")
    func hasShadowIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.hasShadow == true)
    }

    @Test("is movable by window background")
    func isMovableByWindowBackgroundIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.isMovableByWindowBackground == true)
    }
}
