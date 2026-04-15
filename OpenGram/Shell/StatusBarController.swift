import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let stateMachine: IconStateMachine
    private let menuBuilder: MenuBuilder
    private let settingsPanel = LLMSettingsPanel()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        stateMachine = IconStateMachine()
        menuBuilder = MenuBuilder()

        setupButton()
        statusItem.menu = menuBuilder.buildMenu()

        menuBuilder.onSettingsTapped = { [weak self] in
            self?.settingsPanel.show()
        }

        stateMachine.onStateChange = { [weak self] _, symbolName, opacity in
            self?.applyIcon(symbolName: symbolName, opacity: opacity)
        }
    }

    func setState(_ state: AppState) {
        stateMachine.setState(state)
    }

    func triggerSilentFail() {
        stateMachine.triggerSilentFail()
    }

    func updateStatusText(_ text: String) {
        menuBuilder.updateStatusText(text)
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: AppState.idle.sfSymbolName, accessibilityDescription: "OpenGram")
        image?.isTemplate = true
        button.image = image
    }

    private func applyIcon(symbolName: String, opacity: CGFloat) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "OpenGram")
        image?.isTemplate = true
        button.image = image
        button.alphaValue = opacity
    }
}
