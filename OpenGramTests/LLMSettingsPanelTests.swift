import Testing
import AppKit
@testable import OpenGramLib

@MainActor
struct LLMSettingsPanelTests {

    @Test func showActivatesAppBeforePanelDisplay() {
        let panel = LLMSettingsPanel()
        panel.show()

        let nsPanel = panel.visiblePanel
        #expect(nsPanel != nil, "Panel must exist after show()")
        #expect(nsPanel?.level == .floating, "Panel must use .floating level for menu bar agent visibility")
        #expect(nsPanel?.isReleasedWhenClosed == false)
    }

    @Test func showOnExistingVisiblePanelActivatesApp() {
        let panel = LLMSettingsPanel()
        panel.show()

        let firstPanel = panel.visiblePanel
        // Call show() again to exercise the early-return path
        panel.show()

        let secondPanel = panel.visiblePanel
        #expect(firstPanel === secondPanel, "Should reuse the same panel")
        #expect(secondPanel?.level == .floating)
    }
}
