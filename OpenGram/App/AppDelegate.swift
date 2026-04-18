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

        let config = OpenGramConfig()
        let textBox = MainActorTextBox()

        let queue = LLMRequestQueue(
            llm: llmService,
            configProvider: { ConfigManager.currentLLMConfig() },
            apiKeyProvider: { ConfigManager.currentAPIKey() },
            timeoutProvider: { TimeInterval(config.llmRequestTimeoutSeconds) }
        )

        let splitter = ParagraphSplitter(capabilityCache: capabilityCache)

        let store = ParagraphSuggestionStore(
            queue: queue,
            splitter: splitter,
            config: config,
            textProvider: { [textBox] bundleID in textBox.read(bundleID: bundleID) }
        )
        Task { await queue.setStore(store) }

        let statusBarController = StatusBarController()

        let textMonitor = TextMonitor(
            textEngine: textEngine,
            orchestrator: orchestrator,
            capabilityCache: capabilityCache,
            store: store,
            splitter: splitter,
            textBoxWriter: { [textBox] bundleID, text in textBox.write(bundleID: bundleID, text: text) }
        )

        let overlayController = OverlayController(
            textMonitor: textMonitor,
            config: config,
            store: store
        )

        let coordinator = CheckCoordinator(
            textEngine: textEngine,
            orchestrator: orchestrator,
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
