import AppKit
import SwiftUI
import Security

public final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("selectedDialect") private var selectedDialect: String = "US"
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?
    private var permissionGuide: PermissionGuide?
    private var harperService: (any GrammarCheckerProtocol)?
    private var llmService: LLMService?
    private var orchestrator: CheckOrchestrator?
    private var overlayController: OverlayController?
    private var llmPanelController: LLMPanelController?
    private var textMonitor: TextMonitor?
    private var lastExtractedContext: TextContext?
    private var lastSuggestions: [Suggestion] = []
    private var accumulatedSuggestions: [Suggestion] = []
    private var checkTask: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var appWhitelist = AppWhitelist()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let capabilityCache = AXCapabilityCache()
        let textEngine = AXTextEngine(capabilityCache: capabilityCache)
        let hotkeyManager = HotkeyManager()
        let statusBarController = StatusBarController()
        let permissionGuide = PermissionGuide()

        let dictionaryStore = DictionaryStore()
        let harperService = HarperService(dictionaryStore: dictionaryStore, dialect: selectedDialect)
        let llmService = LLMService()
        let orchestrator = CheckOrchestrator(harper: harperService, llm: llmService)

        let overlayController = OverlayController()
        let llmPanelController = LLMPanelController()

        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.textEngine = textEngine
        self.permissionGuide = permissionGuide
        self.harperService = harperService
        self.llmService = llmService
        self.orchestrator = orchestrator
        self.overlayController = overlayController
        self.llmPanelController = llmPanelController

        overlayController.onAcceptSuggestion = { [weak self] suggestion in
            self?.lastSuggestions.removeAll { $0.id == suggestion.id }
            self?.accumulatedSuggestions.removeAll { $0.id == suggestion.id }
        }

        overlayController.onDismissSuggestion = { [weak self] suggestion in
            self?.lastSuggestions.removeAll { $0.id == suggestion.id }
            self?.accumulatedSuggestions.removeAll { $0.id == suggestion.id }
        }

        overlayController.onAddToDictionary = { [weak self] word in
            guard let orchestrator = self?.orchestrator else { return }
            Task {
                await orchestrator.addToDictionary(word: word)
            }
        }

        overlayController.onDismissAll = { [weak self] in
            self?.statusBarController?.setState(.idle)
            self?.statusBarController?.updateStatusText("OpenGram: Ready")
            self?.lastSuggestions = []
            self?.accumulatedSuggestions = []
            self?.lastExtractedContext = nil
        }

        hotkeyManager.onHotkeyFired = { [weak self] in
            self?.handleHotkeyFired()
        }

        let textMonitor = TextMonitor(
            textEngine: textEngine,
            orchestrator: orchestrator,
            capabilityCache: capabilityCache
        )
        self.textMonitor = textMonitor

        textMonitor.llmConfig = Self.currentLLMConfig()
        textMonitor.llmAPIKey = Self.currentAPIKey()

        textMonitor.onCheckComplete = { [weak self] suggestions, context in
            guard let self else { return }
            self.accumulatedSuggestions = suggestions  // Harper results are the base
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

            // If LLM is configured, show spinner while async checks run (D-03)
            let config = Self.currentLLMConfig()
            if config.isEnabled {
                self.statusBarController?.setState(.checkingLLM)
                self.statusBarController?.updateStatusText("Checking style\u{2026}")
            }
        }

        textMonitor.onLLMBatch = { [weak self] styleSuggestions, context in
            guard let self, !styleSuggestions.isEmpty,
                  let bounds = context.elementBounds else { return }

            self.lastExtractedContext = context

            let anchorRect = NSRect(
                x: bounds.origin.x,
                y: bounds.origin.y,
                width: bounds.size.width,
                height: bounds.size.height
            )
            let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorRect) }) ?? NSScreen.main ?? NSScreen.screens[0]

            self.llmPanelController?.show(
                suggestions: styleSuggestions,
                near: anchorRect,
                on: screen,
                onApply: { [weak self] suggestion in
                    self?.applyLLMSuggestion(suggestion)
                },
                onDismiss: { [weak self] in
                    self?.llmPanelController?.dismiss()
                }
            )
        }

        textMonitor.onLLMFinished = { [weak self] in
            guard let self else { return }
            // Stop spinner (D-03)
            if self.accumulatedSuggestions.isEmpty {
                self.statusBarController?.setState(.idle)
                self.statusBarController?.updateStatusText("OpenGram: Ready")
            } else {
                self.statusBarController?.setState(.done)
                self.statusBarController?.updateStatusText("OpenGram: \(self.accumulatedSuggestions.count) suggestion(s)")
            }
        }

        textMonitor.onDismiss = { [weak self] in
            self?.overlayController?.dismiss()
            self?.statusBarController?.setState(.idle)
            self?.statusBarController?.updateStatusText("OpenGram: Ready")
            self?.lastSuggestions = []
            self?.accumulatedSuggestions = []
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
        // Whitelist gate: only check apps where text editing makes sense
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier,
           !appWhitelist.isAllowed(bundleID) {
            statusBarController?.flashInactive()
            return
        }

        overlayController?.dismiss()
        llmPanelController?.dismiss()

        guard let statusBar = statusBarController,
              let engine = textEngine,
              let orchestrator else { return }

        statusBar.setState(.checking)
        statusBar.updateStatusText("OpenGram: Checking...")

        guard let context = engine.extractText() else {
            statusBar.triggerSilentFail()
            statusBar.updateStatusText("OpenGram: Ready")
            return
        }
        lastExtractedContext = context

        // Cancel any in-flight checks before starting new ones
        checkTask?.cancel()
        llmTask?.cancel()

        // Phase 1: Harper check on full text — show underlines immediately
        checkTask = Task {
            let harperSuggestions = await orchestrator.harperOnly(text: context.text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.lastSuggestions = harperSuggestions
                self.accumulatedSuggestions = harperSuggestions
                if harperSuggestions.isEmpty {
                    statusBar.setState(.done)
                    statusBar.updateStatusText("OpenGram: No issues found")
                } else {
                    statusBar.setState(.done)
                    statusBar.updateStatusText("OpenGram: \(harperSuggestions.count) suggestion(s)")
                    self.overlayController?.show(suggestions: harperSuggestions, context: context)
                }
            }
        }

        // Phase 2: LLM async style check — show panel on completion
        let config = Self.currentLLMConfig()
        guard config.isEnabled, let llmService else { return }

        statusBar.setState(.checkingLLM)
        statusBar.updateStatusText("Checking style\u{2026}")

        let paragraph = ParagraphExtractor.extract(from: context)
        let apiKey = Self.currentAPIKey()

        llmTask = Task {
            let styleSuggestions = await llmService.analyze(
                paragraph: paragraph,
                config: config,
                apiKey: apiKey
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Restore status bar now that LLM check is complete
                if self.accumulatedSuggestions.isEmpty {
                    statusBar.setState(.idle)
                    statusBar.updateStatusText("OpenGram: Ready")
                } else {
                    statusBar.setState(.done)
                    statusBar.updateStatusText("OpenGram: \(self.accumulatedSuggestions.count) suggestion(s)")
                }

                guard !styleSuggestions.isEmpty,
                      let bounds = context.elementBounds else { return }

                let anchorRect = NSRect(
                    x: bounds.origin.x,
                    y: bounds.origin.y,
                    width: bounds.size.width,
                    height: bounds.size.height
                )
                let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorRect) }) ?? NSScreen.main ?? NSScreen.screens[0]

                self.llmPanelController?.show(
                    suggestions: styleSuggestions,
                    near: anchorRect,
                    on: screen,
                    onApply: { [weak self] suggestion in
                        self?.applyLLMSuggestion(suggestion)
                    },
                    onDismiss: { [weak self] in
                        self?.llmPanelController?.dismiss()
                    }
                )
            }
        }
    }

    @MainActor
    private func applyLLMSuggestion(_ suggestion: LLMStyleSuggestion) {
        guard let context = lastExtractedContext,
              let engine = textEngine else { return }

        // If the suggestion's originalText matches a user selection, write back via
        // re-selection; otherwise search the full AX value for the substring and replace.
        if let cfRange = context.selectionRange, cfRange.length > 0,
           let selText = ParagraphExtractor.extract(from: context) as String?,
           selText == suggestion.originalText {
            _ = engine.writeBack(context: context, replacement: suggestion.revisedText)
        } else {
            _ = replaceSubstring(
                originalText: suggestion.originalText,
                revisedText: suggestion.revisedText,
                in: context
            )
        }

        llmPanelController?.dismiss()
    }

    /// Searches the current AX element value for `originalText` and replaces the first
    /// occurrence with `revisedText` using a range-targeted AX write.
    @MainActor
    @discardableResult
    private func replaceSubstring(
        originalText: String,
        revisedText: String,
        in context: TextContext
    ) -> Bool {
        guard let engine = textEngine as? AXTextEngine else {
            // Fallback: use writeBack which replaces current selection
            return textEngine?.writeBack(context: context, replacement: revisedText) ?? false
        }

        // Use writeBack after constructing a context whose selectionRange covers originalText
        let fullText = context.text
        guard let range = fullText.range(of: originalText) else {
            return engine.writeBack(context: context, replacement: revisedText)
        }

        let scalars = fullText.unicodeScalars
        let start = scalars.distance(from: scalars.startIndex, to: range.lowerBound)
        let length = scalars.distance(from: range.lowerBound, to: range.upperBound)
        let cfRange = CFRange(location: start, length: length)

        let adjustedContext = TextContext(
            text: fullText,
            bundleID: context.bundleID,
            extractionMethod: context.extractionMethod,
            selectionRange: cfRange,
            elementBounds: context.elementBounds,
            axElement: context.axElement
        )
        return engine.writeBack(context: adjustedContext, replacement: revisedText)
    }

    static func currentLLMConfig() -> LLMConfig {
        let defaults = UserDefaults.standard
        return LLMConfig(
            baseURL: defaults.string(forKey: "llmBaseURL") ?? LLMConfig.default.baseURL,
            model: defaults.string(forKey: "llmModel") ?? LLMConfig.default.model,
            enabledChecks: {
                var checks = Set<LLMCheckType>()
                if defaults.object(forKey: "llmEnableTone") == nil || defaults.bool(forKey: "llmEnableTone") { checks.insert(.tone) }
                if defaults.object(forKey: "llmEnableClarity") == nil || defaults.bool(forKey: "llmEnableClarity") { checks.insert(.clarity) }
                if defaults.object(forKey: "llmEnableRephrase") == nil || defaults.bool(forKey: "llmEnableRephrase") { checks.insert(.rephrase) }
                return checks
            }(),
            temperature: defaults.object(forKey: "llmTemperature") != nil
                ? defaults.double(forKey: "llmTemperature")
                : LLMConfig.default.temperature,
            maxTokens: LLMConfig.default.maxTokens,
            requestTimeout: defaults.object(forKey: "llmRequestTimeout") != nil
                ? defaults.double(forKey: "llmRequestTimeout")
                : LLMConfig.default.requestTimeout
        )
    }

    static func currentAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.opengram.llm",
            kSecAttrAccount: "apiKey",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }
}
