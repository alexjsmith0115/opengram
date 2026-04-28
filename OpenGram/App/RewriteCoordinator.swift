import AppKit
import os.log

// MARK: - Controller protocol (testability seam)

@MainActor
protocol RewriteWindowControlling: AnyObject {
    func show(near bounds: CGRect?) -> Bool
    func hide()
    func teardownForSessionReplacement()
    func teardownForFailedShow()
}

extension RewriteWindowController: RewriteWindowControlling {}

// MARK: - Text engine / replacer protocols (testability seam)

@MainActor
protocol RewriteTextEngineProtocol: AnyObject {
    func extractText() -> TextContext?
    func readLiveText(at range: CFRange, of element: AXUIElement) -> String?
    func readLiveSelectedText(of element: AXUIElement) -> String?
}

extension AXTextEngine: RewriteTextEngineProtocol {}

@MainActor
protocol RewriteTextReplacerProtocol: AnyObject {
    @discardableResult
    func replace(strategy: WriteBackStrategy,
                 replacement: String,
                 element: AXUIElement) -> Bool
}

extension AXTextReplacer: RewriteTextReplacerProtocol {}


// MARK: - Coordinator

@MainActor
final class RewriteCoordinator {
    private static let logger = Log.logger(for: "RewriteCoordinator")

    typealias ControllerBuilder = @MainActor (
        _ vm: RewriteWindowViewModel,
        _ onApply: @escaping () -> Void,
        _ onCancel: @escaping () -> Void,
        _ onOpenSettings: @escaping () -> Void
    ) -> RewriteWindowControlling

    private let textEngine: any RewriteTextEngineProtocol
    private let textReplacer: any RewriteTextReplacerProtocol
    private let llmService: LLMService
    private let configManager: any RewriteConfigProvider
    private let statusBar: StatusBarController
    private let openSettings: () -> Void
    private let buildController: ControllerBuilder

    private var current: (controller: RewriteWindowControlling,
                          viewModel: RewriteWindowViewModel,
                          context: RewriteCaptureContext)?

    init(
        textEngine: any RewriteTextEngineProtocol,
        textReplacer: any RewriteTextReplacerProtocol,
        llmService: LLMService,
        configManager: any RewriteConfigProvider,
        statusBar: StatusBarController,
        openSettings: @escaping () -> Void,
        buildController: @escaping ControllerBuilder = { vm, apply, cancel, settings in
            RewriteWindowController(
                viewModel: vm,
                onApply: apply,
                onCancel: cancel,
                onOpenSettings: settings
            )
        }
    ) {
        self.textEngine = textEngine
        self.textReplacer = textReplacer
        self.llmService = llmService
        self.configManager = configManager
        self.statusBar = statusBar
        self.openSettings = openSettings
        self.buildController = buildController
    }

    func handleRewriteHotkey() {
        // 1. Capture (read-only). Old window untouched on failure.
        guard let textCtx = textEngine.extractText(),
              !textCtx.text.isEmpty,
              let strategy = WriteBackStrategy.choose(
                  range: textCtx.selectionRange,
                  caps: textCtx.capabilities
              )
        else {
            statusBar.flashSelectTextHint()
            return
        }

        // 2. Build new context + view model + controller (no UI side effects).
        let ctx = RewriteCaptureContext(
            capturedOriginal: textCtx.text,
            writeBackStrategy: strategy,
            capabilities: textCtx.capabilities,
            axElement: textCtx.axElement,
            bundleID: textCtx.bundleID,
            elementBounds: textCtx.elementBounds
        )

        let llmAdapter = LLMRewriteAdapter(
            service: llmService,
            config: configManager.llmConfig,
            apiKey: configManager.currentAPIKey()
        )
        let vm = RewriteWindowViewModel(
            original: ctx.capturedOriginal,
            llm: llmAdapter,
            configManager: configManager
        )
        let newController = buildController(
            vm,
            { [weak self] in self?.apply() },
            { [weak self] in self?.dismiss() },
            { [weak self] in self?.openSettings() }
        )

        // 3. Tear down prior visible session silently.
        if let prior = current {
            prior.controller.teardownForSessionReplacement()
            current = nil
        }

        // 4. Show new. On failure, roll back without firing user callbacks.
        let didShow = newController.show(near: ctx.elementBounds)
        guard didShow else {
            newController.teardownForFailedShow()
            statusBar.flashError("Couldn't open rewrite window. Try again.")
            return
        }

        // 5. Commit as current.
        current = (newController, vm, ctx)
    }

    func apply() {
        guard let cur = current else { return }
        let live: String?
        switch cur.context.writeBackStrategy {
        case .rangeAndSelectedText(let r), .valueSplice(let r):
            live = textEngine.readLiveText(at: r, of: cur.context.axElement)
        case .selectedTextOnly:
            live = textEngine.readLiveSelectedText(of: cur.context.axElement)
        }
        guard let live else {
            cur.viewModel.setError(.targetUnavailable, attemptedTone: nil)
            return
        }
        guard live == cur.context.capturedOriginal else {
            cur.viewModel.setError(.targetChanged, attemptedTone: nil)
            return
        }
        let ok = textReplacer.replace(
            strategy: cur.context.writeBackStrategy,
            replacement: cur.viewModel.revised,
            element: cur.context.axElement
        )
        if ok {
            dismiss()
        } else {
            cur.viewModel.setError(
                .writeFailed(bundleID: cur.context.bundleID),
                attemptedTone: nil
            )
        }
    }

    func dismiss() {
        current?.controller.hide()
        current = nil
    }

    // MARK: Internal test surface

    var currentSnapshotIsNil: Bool { current == nil }
    func applyForTest() { apply() }
}

// MARK: - LLM adapter

private struct LLMRewriteAdapter: RewriteLLMProvider {
    let service: LLMService
    let config: LLMConfig
    let apiKey: String?

    func rewrite(text: String, tone: RewriteTone) async throws -> String {
        try await service.rewrite(text: text, tone: tone, config: config, apiKey: apiKey)
    }
}
