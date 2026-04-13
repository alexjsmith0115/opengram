import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?
    private var permissionGuide: PermissionGuide?
    private var lastExtractedContext: TextContext?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let capabilityCache = AXCapabilityCache()
        let textEngine = AXTextEngine(capabilityCache: capabilityCache)
        let hotkeyManager = HotkeyManager()
        let statusBarController = StatusBarController()
        let permissionGuide = PermissionGuide()

        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.textEngine = textEngine
        self.permissionGuide = permissionGuide

        hotkeyManager.onHotkeyFired = { [weak self] in
            self?.handleHotkeyFired()
        }

        hotkeyManager.install()
        permissionGuide.showIfNeeded()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.uninstall()
    }

    @MainActor
    private func handleHotkeyFired() {
        guard let statusBar = statusBarController,
              let engine = textEngine else { return }

        statusBar.setState(.checking)
        statusBar.updateStatusText("OpenGram: Checking...")

        guard let context = engine.extractText() else {
            statusBar.triggerSilentFail()
            statusBar.updateStatusText("OpenGram: Ready")
            return
        }

        print("[OpenGram] Extracted text from \(context.bundleID) via \(context.extractionMethod.rawValue): \(context.text.prefix(80))...")

        statusBar.setState(.done)
        statusBar.updateStatusText("OpenGram: Ready")

        lastExtractedContext = context
    }
}
