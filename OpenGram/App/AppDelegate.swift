import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("selectedDialect") private var selectedDialect: String = "US"
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?
    private var permissionGuide: PermissionGuide?
    private var harperService: (any GrammarCheckerProtocol)?
    private var lastExtractedContext: TextContext?
    private var lastSuggestions: [Suggestion] = []

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let capabilityCache = AXCapabilityCache()
        let textEngine = AXTextEngine(capabilityCache: capabilityCache)
        let hotkeyManager = HotkeyManager()
        let statusBarController = StatusBarController()
        let permissionGuide = PermissionGuide()

        let dictionaryStore = DictionaryStore()
        let harperService = HarperService(dictionaryStore: dictionaryStore, dialect: selectedDialect)

        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.textEngine = textEngine
        self.permissionGuide = permissionGuide
        self.harperService = harperService

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
              let engine = textEngine,
              let harperService = harperService else { return }

        statusBar.setState(.checking)
        statusBar.updateStatusText("OpenGram: Checking...")

        guard let context = engine.extractText() else {
            statusBar.triggerSilentFail()
            statusBar.updateStatusText("OpenGram: Ready")
            return
        }

        lastExtractedContext = context

        Task {
            let suggestions = await harperService.check(text: context.text)
            await MainActor.run {
                self.lastSuggestions = suggestions
                print("[OpenGram] Harper found \(suggestions.count) suggestion(s)")
                statusBar.setState(.done)
                statusBar.updateStatusText("OpenGram: Ready")
            }
        }
    }
}
