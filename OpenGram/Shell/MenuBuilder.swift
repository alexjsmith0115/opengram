import AppKit

final class MenuBuilder {
    private(set) var statusMenuItem: NSMenuItem!

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "OpenGram: Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.attributedTitle = NSAttributedString(
            string: "OpenGram: Ready",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        menu.addItem(statusMenuItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: "")
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

    func updateStatusText(_ text: String) {
        statusMenuItem?.title = text
        statusMenuItem?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
    }
}
