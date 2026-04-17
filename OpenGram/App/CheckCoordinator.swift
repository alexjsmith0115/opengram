@preconcurrency import ApplicationServices
import AppKit
import os.log

/// Owns the check-display pipeline: hotkey handling, suggestion state, LLM application.
/// Extracted from AppDelegate to separate lifecycle from check orchestration.
@MainActor
final class CheckCoordinator {
    private static let logger = Log.logger(for: "CheckCoordinator")

    // MARK: - Dependencies

    private let textEngine: any AXTextEngineProtocol
    private let orchestrator: CheckOrchestrator
    private let scheduler: LLMCheckScheduler
    let overlayController: OverlayController
    let statusBarController: StatusBarController
    var appWhitelist: AppWhitelist

    // MARK: - State

    private(set) var lastExtractedContext: TextContext?
    private(set) var lastSuggestions: [Suggestion] = []
    private(set) var accumulatedSuggestions: [Suggestion] = []
    private var checkTask: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?

    init(
        textEngine: any AXTextEngineProtocol,
        orchestrator: CheckOrchestrator,
        scheduler: LLMCheckScheduler,
        overlayController: OverlayController,
        statusBarController: StatusBarController,
        appWhitelist: AppWhitelist
    ) {
        self.textEngine = textEngine
        self.orchestrator = orchestrator
        self.scheduler = scheduler
        self.overlayController = overlayController
        self.statusBarController = statusBarController
        self.appWhitelist = appWhitelist

        wireOverlayCallbacks()
    }

    // MARK: - Callback wiring

    private func wireOverlayCallbacks() {
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
            Task { await orchestrator.addToDictionary(word: word) }
        }

        overlayController.onDismissAll = { [weak self] in
            self?.resetState()
        }
    }

    // MARK: - Hotkey handling

    func handleHotkeyFired() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier,
              appWhitelist.isAllowed(bundleID) else {
            statusBarController.flashInactive()
            return
        }

        overlayController.dismiss()

        statusBarController.setState(.checking)
        statusBarController.updateStatusText("OpenGram: Checking...")

        guard let context = textEngine.extractText() else {
            statusBarController.triggerSilentFail()
            statusBarController.updateStatusText("OpenGram: Ready")
            return
        }
        lastExtractedContext = context

        checkTask?.cancel()
        llmTask?.cancel()

        checkTask = Task {
            let harperSuggestions = await orchestrator.harperOnly(text: context.text)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.lastSuggestions = harperSuggestions
                self.accumulatedSuggestions = harperSuggestions
                if harperSuggestions.isEmpty {
                    self.statusBarController.setState(.done)
                    self.statusBarController.updateStatusText("OpenGram: No issues found")
                } else {
                    self.statusBarController.setState(.done)
                    self.statusBarController.updateStatusText("OpenGram: \(harperSuggestions.count) suggestion(s)")
                    self.overlayController.show(suggestions: harperSuggestions, context: context)
                }
            }
        }

        let config = ConfigManager.currentLLMConfig()
        guard config.isEnabled else {
            Self.logger.debug("LLM skipped — isEnabled=\(config.isEnabled)")
            return
        }

        statusBarController.setState(.checkingLLM)
        statusBarController.updateStatusText("Checking style\u{2026}")

        let contextBundleID = context.bundleID
        let contextText = context.text
        let harperCheckTask = checkTask
        let scheduler = self.scheduler

        llmTask = Task {
            await harperCheckTask?.value
            guard !Task.isCancelled else {
                Self.logger.info("llmTask cancelled after Harper wait")
                return
            }

            let harperSpans = await MainActor.run { self.lastSuggestions.map { $0.original } }
            Self.logger.info("llmTask calling scheduler.check — textLen=\(contextText.count) harperSpans=\(harperSpans.count)")
            let schedulerSuggestions = await scheduler.check(text: contextText, bundleID: contextBundleID, harperSpans: harperSpans)
            guard !Task.isCancelled else {
                Self.logger.info("llmTask cancelled after scheduler.check")
                return
            }
            Self.logger.info("llmTask scheduler returned \(schedulerSuggestions.count) total suggestion(s)")

            await MainActor.run {
                self.restoreStatusAfterLLM()

                let llmSuggestions = schedulerSuggestions.filter { $0.source == .llm }
                Self.logger.info("llmTask filter — llmSuggestions=\(llmSuggestions.count) accumulatedHarper=\(self.accumulatedSuggestions.count)")
                if !llmSuggestions.isEmpty {
                    let merged = self.accumulatedSuggestions + llmSuggestions
                    Self.logger.info("llmTask calling overlayController.update with merged=\(merged.count)")
                    self.overlayController.update(suggestions: merged, context: context)
                } else {
                    Self.logger.info("llmTask skipping update — no .llm suggestions in scheduler output")
                }
            }
        }
    }

    // MARK: - TextMonitor callbacks

    func handleCheckComplete(_ suggestions: [Suggestion], _ context: TextContext) {
        accumulatedSuggestions = suggestions
        lastSuggestions = suggestions
        lastExtractedContext = context

        if suggestions.isEmpty {
            overlayController.dismiss()
            statusBarController.setState(.idle)
            statusBarController.updateStatusText("OpenGram: Ready")
        } else {
            statusBarController.setState(.done)
            statusBarController.updateStatusText("OpenGram: \(suggestions.count) suggestion(s)")
            overlayController.update(suggestions: suggestions, context: context)
        }

        let config = ConfigManager.currentLLMConfig()
        if config.isEnabled {
            statusBarController.setState(.checkingLLM)
            statusBarController.updateStatusText("Checking style\u{2026}")
        }
    }

    func handleLLMFinished() {
        restoreStatusAfterLLM()
    }

    func handleDismiss() {
        overlayController.dismiss()
        resetState()
    }

    // MARK: - Private helpers

    private func resetState() {
        statusBarController.setState(.idle)
        statusBarController.updateStatusText("OpenGram: Ready")
        lastSuggestions = []
        accumulatedSuggestions = []
        lastExtractedContext = nil
    }

    private func restoreStatusAfterLLM() {
        if accumulatedSuggestions.isEmpty {
            statusBarController.setState(.idle)
            statusBarController.updateStatusText("OpenGram: Ready")
        } else {
            statusBarController.setState(.done)
            statusBarController.updateStatusText("OpenGram: \(accumulatedSuggestions.count) suggestion(s)")
        }
    }
}
