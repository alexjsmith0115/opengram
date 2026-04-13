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

    @Test("becomesKeyOnlyIfNeeded is true")
    func becomesKeyOnlyIfNeededIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.becomesKeyOnlyIfNeeded == true)
    }
}
