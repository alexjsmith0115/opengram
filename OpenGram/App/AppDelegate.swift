import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("selectedDialect") private var selectedDialect: String = "US"
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textMonitor: TextMonitor?
    private var permissionGuide: PermissionGuide?
    private var checkCoordinator: CheckCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let capabilityCache = AXCapabilityCache()
        let textEngine = AXTextEngine(capabilityCache: capabilityCache)
        let hotkeyManager = HotkeyManager()
        let permissionGuide = PermissionGuide()

        let dictionaryStore = DictionaryStore()
        let harperService = HarperService(dictionaryStore: dictionaryStore, dialect: selectedDialect)
        let llmService = LLMService()
        let orchestrator = CheckOrchestrator(harper: harperService)

        // D-13: Scheduler is DI-composed at the root. Concrete Phase 15 components passed in;
        // flag is read live per-call via UserDefaultsIncrementalConfig (D-14).
        let scheduler = LLMCheckScheduler(
            splitter: DoubleNewlineSplitter(),
            hasher: Sha256ParagraphHasher(),
            cache: ParagraphSuggestionCache(),
            clock: SystemClock(),
            llm: llmService,
            configProvider: { ConfigManager.currentLLMConfig() },
            apiKeyProvider: { ConfigManager.currentAPIKey() },
            incrementalConfig: UserDefaultsIncrementalConfig()
        )

        let statusBarController = StatusBarController()

        // TextMonitor constructed before OverlayController so it can be DI-injected.
        // RephraseCardPanelController (Phase 18) installs its own onKeystroke subscription
        // on show() and restores prior value on hide() — AppDelegate stays out of that chain.
        let textMonitor = TextMonitor(
            textEngine: textEngine,
            orchestrator: orchestrator,
            capabilityCache: capabilityCache
        )

        let overlayController = OverlayController(
            scheduler: scheduler,
            textMonitor: textMonitor,
            incrementalConfig: UserDefaultsIncrementalConfig()
        )

        let coordinator = CheckCoordinator(
            textEngine: textEngine,
            orchestrator: orchestrator,
            scheduler: scheduler,
            overlayController: overlayController,
            statusBarController: statusBarController,
            appWhitelist: AppWhitelist()
        )

        self.hotkeyManager = hotkeyManager
        self.permissionGuide = permissionGuide
        self.checkCoordinator = coordinator
        self.textMonitor = textMonitor

        hotkeyManager.onHotkeyFired = { [weak coordinator] in
            coordinator?.handleHotkeyFired()
        }

        textMonitor.onCheckComplete = { [weak coordinator] suggestions, context in
            coordinator?.handleCheckComplete(suggestions, context)
        }

        textMonitor.onLLMFinished = { [weak coordinator] in
            coordinator?.handleLLMFinished()
        }

        textMonitor.onDismiss = { [weak coordinator] in
            coordinator?.handleDismiss()
        }

        textMonitor.start()
        hotkeyManager.install()
        permissionGuide.showIfNeeded()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        textMonitor?.stop()
        hotkeyManager?.uninstall()
    }
}
