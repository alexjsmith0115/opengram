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
    private var textMonitor: TextMonitor?
    private var lastExtractedContext: TextContext?
    private var lastSuggestions: [Suggestion] = []
    private var accumulatedSuggestions: [Suggestion] = []
    private var checkTask: Task<Void, Never>?

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

        self.statusBarController = statusBarController
        self.hotkeyManager = hotkeyManager
        self.textEngine = textEngine
        self.permissionGuide = permissionGuide
        self.harperService = harperService
        self.llmService = llmService
        self.orchestrator = orchestrator
        self.overlayController = overlayController

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

        textMonitor.onLLMBatch = { [weak self] newBatch, context in
            guard let self else { return }
            self.accumulatedSuggestions.append(contentsOf: newBatch)
            self.lastSuggestions = self.accumulatedSuggestions
            self.overlayController?.update(suggestions: self.accumulatedSuggestions, context: context)
            self.statusBarController?.updateStatusText("OpenGram: \(self.accumulatedSuggestions.count) suggestion(s)")
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
        guard let statusBar = statusBarController else { return }

        statusBar.setState(.checking)
        statusBar.updateStatusText("OpenGram: Checking...")

        if let textMonitor {
            textMonitor.forceCheckNow()
        } else {
            // Fallback: direct check (should not happen in normal operation)
            guard let engine = textEngine,
                  let orchestrator else { return }
            overlayController?.dismiss()
            guard let context = engine.extractText() else {
                statusBar.triggerSilentFail()
                statusBar.updateStatusText("OpenGram: Ready")
                return
            }
            lastExtractedContext = context
            checkTask?.cancel()
            checkTask = Task {
                let suggestions = await orchestrator.harperOnly(text: context.text)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.lastSuggestions = suggestions
                    self.accumulatedSuggestions = suggestions
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
