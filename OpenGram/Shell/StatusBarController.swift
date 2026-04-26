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
            Task { @MainActor in
                self?.settingsPanel.show()
            }
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

    /// Brief dim→restore animation indicating the hotkey fired in a non-whitelisted app.
    func flashInactive() {
        guard let button = statusItem.button else { return }
        button.alphaValue = 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak button] in
            button?.alphaValue = 1.0
        }
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
