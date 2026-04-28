import Testing
import AppKit

@testable import OpenGramLib

private final class FittingTestView: NSView {
    private let testFittingSize: NSSize

    init(fittingSize: NSSize) {
        self.testFittingSize = fittingSize
        super.init(frame: NSRect(origin: .zero, size: fittingSize))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var fittingSize: NSSize { testFittingSize }
}

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

    @Test("window is non-opaque so transparent rounded corners composite correctly")
    func isOpaqueIsFalse() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.isOpaque == false)
    }

    @Test("hasShadow is false so AppKit does not draw a rectangular shadow under the rounded card")
    func hasShadowIsFalse() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.hasShadow == false)
    }

    @Test("is movable by window background")
    func isMovableByWindowBackgroundIsTrue() {
        let panel = SuggestionPopoverPanel()
        #expect(panel.isMovableByWindowBackground == true)
    }

    @Test("setContent resizes panel to hosted view fitting size")
    func setContentResizesToFittingSize() {
        let panel = SuggestionPopoverPanel()
        let view = FittingTestView(fittingSize: NSSize(width: 340, height: 220))

        panel.setContent(view)

        #expect(panel.contentView === view)
        #expect(panel.contentView?.frame.size.width == 340)
        #expect(panel.contentView?.frame.size.height == 220)
    }

    @Test("setContent clamps hosted view width to popover maximum plus shadow padding")
    func setContentClampsWidthToMaximum() {
        let panel = SuggestionPopoverPanel()
        let view = FittingTestView(fittingSize: NSSize(width: 500, height: 180))

        panel.setContent(view)

        #expect(panel.contentView?.frame.size.width == 388)
        #expect(panel.contentView?.frame.size.height == 180)
    }
}
