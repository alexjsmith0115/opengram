import AppKit
import ApplicationServices

@MainActor
final class PermissionGuide {
    private var panel: NSPanel?

    func showIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        showWelcomePanel()
    }

    private func showWelcomePanel() {
        let panelWidth: CGFloat = 480
        let horizontalPadding: CGFloat = 16
        let topPadding: CGFloat = 32
        let contentWidth = panelWidth - (horizontalPadding * 2)

        let contentView = NSView()
        var yOffset: CGFloat = 0

        // "Not now" link (bottom-most, laid out first for upward stacking)
        let dismissButton = NSButton(title: "Not now", target: nil, action: nil)
        dismissButton.isBordered = false
        dismissButton.font = NSFont.systemFont(ofSize: 13)
        dismissButton.contentTintColor = NSColor.secondaryLabelColor
        dismissButton.keyEquivalent = "\u{1b}"
        dismissButton.sizeToFit()
        dismissButton.frame = NSRect(
            x: (panelWidth - dismissButton.frame.width) / 2,
            y: yOffset,
            width: dismissButton.frame.width,
            height: dismissButton.frame.height
        )
        contentView.addSubview(dismissButton)
        yOffset += dismissButton.frame.height + 8

        // CTA button
        let ctaButton = NSButton(title: "Open System Settings", target: nil, action: nil)
        ctaButton.bezelStyle = .rounded
        ctaButton.controlSize = .large
        ctaButton.font = NSFont.systemFont(ofSize: 13)
        ctaButton.contentTintColor = NSColor.controlAccentColor
        ctaButton.keyEquivalent = "\r"
        ctaButton.sizeToFit()
        let ctaWidth = max(ctaButton.frame.width + 24, 200)
        ctaButton.frame = NSRect(
            x: (panelWidth - ctaWidth) / 2,
            y: yOffset,
            width: ctaWidth,
            height: ctaButton.frame.height
        )
        contentView.addSubview(ctaButton)
        yOffset += ctaButton.frame.height + 24

        // Body text
        let bodyText = """
        OpenGram reads and writes text in other apps using the macOS Accessibility API. \
        This lets you press Ctrl+Shift+G in any app to check and correct your writing.

        To grant access, click the button below and enable OpenGram in \
        System Settings > Privacy & Security > Accessibility.
        """
        let bodyLabel = NSTextField(wrappingLabelWithString: bodyText)
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.alignment = .center
        bodyLabel.isSelectable = false
        bodyLabel.frame = NSRect(x: horizontalPadding, y: yOffset, width: contentWidth, height: 0)
        bodyLabel.preferredMaxLayoutWidth = contentWidth
        bodyLabel.sizeToFit()
        bodyLabel.frame = NSRect(
            x: horizontalPadding,
            y: yOffset,
            width: contentWidth,
            height: bodyLabel.frame.height
        )
        contentView.addSubview(bodyLabel)
        yOffset += bodyLabel.frame.height + 8

        // Title
        let titleLabel = NSTextField(labelWithString: "OpenGram needs Accessibility access")
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(
            x: (panelWidth - titleLabel.frame.width) / 2,
            y: yOffset,
            width: titleLabel.frame.width,
            height: titleLabel.frame.height
        )
        contentView.addSubview(titleLabel)
        yOffset += titleLabel.frame.height + 12

        // App icon
        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(
            x: (panelWidth - 64) / 2,
            y: yOffset,
            width: 64,
            height: 64
        )
        contentView.addSubview(iconView)
        yOffset += 64 + topPadding

        let panelHeight = max(yOffset, 280)
        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.contentView = contentView
        panel.center()
        panel.isMovable = true

        ctaButton.target = self
        ctaButton.action = #selector(openSystemSettings)
        dismissButton.target = self
        dismissButton.action = #selector(dismissPanel)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        panel?.close()
        panel = nil
    }

    @objc private func dismissPanel() {
        panel?.close()
        panel = nil
    }
}
