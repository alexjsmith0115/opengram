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
    private var textMonitor: TextMonitor?
    private var lastExtractedContext: TextContext?
    private var lastSuggestions: [Suggestion] = []
    private var checkTask: Task<Void, Never>?

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

        let textMonitor = TextMonitor(
            textEngine: textEngine,
            harperService: harperService,
            capabilityCache: capabilityCache
        )
        self.textMonitor = textMonitor

        textMonitor.onCheckComplete = { [weak self] suggestions, context in
            guard let self else { return }
            self.lastSuggestions = suggestions
            self.lastExtractedContext = context

            if suggestions.isEmpty {
                self.overlayController?.dismiss()
                self.statusBarController?.setState(.idle)
                self.statusBarController?.updateStatusText("OpenGram: Ready")
            } else {
                self.statusBarController?.setState(.done)
                self.statusBarController?.updateStatusText("OpenGram: \(suggestions.count) suggestion(s)")
                self.overlayController?.update(suggestions: suggestions, context: context)
            }
        }

        textMonitor.onDismiss = { [weak self] in
            self?.overlayController?.dismiss()
            self?.statusBarController?.setState(.idle)
            self?.statusBarController?.updateStatusText("OpenGram: Ready")
            self?.lastSuggestions = []
            self?.lastExtractedContext = nil
        }

        textMonitor.start()

        hotkeyManager.install()
        permissionGuide.showIfNeeded()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        textMonitor?.stop()
        hotkeyManager?.uninstall()
    }

    @MainActor
    private func handleHotkeyFired() {
        guard let statusBar = statusBarController else { return }

        statusBar.setState(.checking)
        statusBar.updateStatusText("OpenGram: Checking...")

        if let textMonitor {
            textMonitor.forceCheckNow()
        } else {
            // Fallback: direct check (should not happen in normal operation)
            guard let engine = textEngine,
                  let harperService = harperService else { return }
            overlayController?.dismiss()
            guard let context = engine.extractText() else {
                statusBar.triggerSilentFail()
                statusBar.updateStatusText("OpenGram: Ready")
                return
            }
            lastExtractedContext = context
            checkTask?.cancel()
            checkTask = Task {
                let suggestions = await harperService.check(text: context.text)
                guard !Task.isCancelled else { return }
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
}
