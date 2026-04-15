import AppKit

final class MenuBuilder: NSObject {
    private(set) var statusMenuItem: NSMenuItem!
    var onSettingsTapped: (() -> Void)?

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "OpenGram: Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.attributedTitle = NSAttributedString(
            string: "OpenGram: Ready",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        menu.addItem(statusMenuItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit OpenGram",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func settingsClicked() {
        onSettingsTapped?()
    }

    func updateStatusText(_ text: String) {
        statusMenuItem?.title = text
        statusMenuItem?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
    }
}
