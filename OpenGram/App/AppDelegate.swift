import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("selectedDialect") private var selectedDialect: String = "US"
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?
    private var permissionGuide: PermissionGuide?
    private var harperService: (any GrammarCheckerProtocol)?
    private var overlayController: OverlayController?
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

        let overlayController = OverlayController()

        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.textEngine = textEngine
        self.permissionGuide = permissionGuide
        self.harperService = harperService
        self.overlayController = overlayController

        overlayController.onAcceptSuggestion = { [weak self] suggestion in
            self?.lastSuggestions.removeAll { $0.id == suggestion.id }
        }

        overlayController.onDismissSuggestion = { [weak self] suggestion in
            self?.lastSuggestions.removeAll { $0.id == suggestion.id }
        }

        overlayController.onAddToDictionary = { [weak self] word in
            guard let harperService = self?.harperService else { return }
            Task {
                await harperService.addToDictionary(word: word)
            }
        }

        overlayController.onDismissAll = { [weak self] in
            self?.statusBarController?.setState(.idle)
            self?.statusBarController?.updateStatusText("OpenGram: Ready")
            self?.lastSuggestions = []
            self?.lastExtractedContext = nil
        }

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

        // Dismiss any existing overlay before starting a new check cycle
        overlayController?.dismiss()

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

                if suggestions.isEmpty {
                    statusBar.setState(.done)
                    statusBar.updateStatusText("OpenGram: No issues found")
                } else {
                    statusBar.setState(.done)
                    statusBar.updateStatusText("OpenGram: \(suggestions.count) suggestion(s)")
                    self.overlayController?.show(suggestions: suggestions, context: context)
                }
            }
        }
    }
}
