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
    let llmPanelController: any LLMPanelShowing
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
        llmPanelController: any LLMPanelShowing,
        statusBarController: StatusBarController,
        appWhitelist: AppWhitelist
    ) {
        self.textEngine = textEngine
        self.orchestrator = orchestrator
        self.scheduler = scheduler
        self.overlayController = overlayController
        self.llmPanelController = llmPanelController
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
        llmPanelController.dismiss()

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

            // D-12: route the hotkey LLM leg through the scheduler. Under flag-off this is a
            // byte-identical pre-v1.2 call; under flag-on it fans out per-paragraph with the
            // cache. harperSpans forwarded either way (LLM-03/LLM-04).
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

                // Merge scheduler's LLM Suggestions into the overlay so tryDispatchRephraseCard
                // receives non-empty llmInRange. accumulatedSuggestions stays Harper-only (state
                // semantics unchanged); merged array is ephemeral, passed only to update().
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

    func handleLLMBatch(_ styleSuggestions: [LLMStyleSuggestion], _ context: TextContext) {
        guard !styleSuggestions.isEmpty, context.elementBounds != nil else { return }
        lastExtractedContext = context
        showLLMPanel(styleSuggestions, context: context)
    }

    func handleLLMFinished() {
        restoreStatusAfterLLM()
    }

    func handleDismiss() {
        overlayController.dismiss()
        resetState()
    }

    // MARK: - LLM suggestion application

    func applyLLMSuggestion(_ suggestion: LLMStyleSuggestion) {
        guard let context = lastExtractedContext else { return }

        if let cfRange = context.selectionRange, cfRange.length > 0,
           let selText = ParagraphExtractor.extract(from: context) as String?,
           selText == suggestion.originalText {
            _ = textEngine.writeBack(context: context, replacement: suggestion.revisedText)
        } else {
            _ = replaceSubstring(
                originalText: suggestion.originalText,
                revisedText: suggestion.revisedText,
                in: context
            )
        }

        llmPanelController.dismiss()
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

    private func showLLMPanel(_ suggestions: [LLMStyleSuggestion], context: TextContext) {
        guard !suggestions.isEmpty, let bounds = context.elementBounds else { return }

        let anchorRect = NSRect(
            x: bounds.origin.x, y: bounds.origin.y,
            width: bounds.size.width, height: bounds.size.height
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorRect) })
            ?? NSScreen.main ?? NSScreen.screens[0]

        llmPanelController.show(
            suggestions: suggestions, near: anchorRect, on: screen,
            onApply: { [weak self] s in self?.applyLLMSuggestion(s) },
            onDismiss: { [weak self] in self?.llmPanelController.dismiss() }
        )
    }

    @discardableResult
    private func replaceSubstring(
        originalText: String, revisedText: String, in context: TextContext
    ) -> Bool {
        guard let engine = textEngine as? AXTextEngine else {
            return textEngine.writeBack(context: context, replacement: revisedText)
        }

        let fullText = context.text
        guard let range = fullText.range(of: originalText) else {
            return engine.writeBack(context: context, replacement: revisedText)
        }

        let scalars = fullText.unicodeScalars
        let start = scalars.distance(from: scalars.startIndex, to: range.lowerBound)
        let length = scalars.distance(from: range.lowerBound, to: range.upperBound)
        let cfRange = CFRange(location: start, length: length)

        let adjustedContext = TextContext(
            text: fullText, bundleID: context.bundleID,
            extractionMethod: context.extractionMethod, selectionRange: cfRange,
            elementBounds: context.elementBounds, axElement: context.axElement
        )
        return engine.writeBack(context: adjustedContext, replacement: revisedText)
    }
}
