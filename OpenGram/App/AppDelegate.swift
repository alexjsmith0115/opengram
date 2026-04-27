import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("selectedDialect") private var selectedDialect: String = "US"
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textMonitor: TextMonitor?
    private var permissionGuide: PermissionGuide?
    private var checkCoordinator: CheckCoordinator?
    private var harperService: HarperService?
    private var clarityObserver: NSObjectProtocol?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let capabilityCache = AXCapabilityCache()
        let textEngine = AXTextEngine(capabilityCache: capabilityCache)
        let hotkeyManager = HotkeyManager()
        let permissionGuide = PermissionGuide()

        let dictionaryStore = DictionaryStore()
        let harperService = HarperService(dictionaryStore: dictionaryStore, dialect: selectedDialect)
        self.harperService = harperService
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
            textBoxWriter: { [textBox] bundleID, text in textBox.write(bundleID: bundleID, text: text) },
            config: config
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

        hotkeyManager.onHotkeyFired = { [weak coordinator, weak textMonitor] _ in
            textMonitor?.reconcileNow()
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

        // Master clarity toggle → setRuleEnabled("WordyPhrases", _) without relaunch (CLAR-07).
        // Use object(forKey:) as? Bool ?? true because @AppStorage defaults are not
        // persisted until user interaction; .bool(forKey:) would return false for unset keys.
        clarityObserver = NotificationCenter.default.addObserver(
            forName: .clarityMasterDidChange,
            object: nil,
            queue: .main
        ) { [weak harperService] _ in
            let key = ClarityKeys.clarityEnabledKey
            let enabled = (UserDefaults.standard.object(forKey: key) as? Bool)
                ?? ClarityKeys.defaultClarityEnabled
            Task { [weak harperService] in
                await harperService?.setRuleEnabled(key: "WordyPhrases", enabled: enabled)
            }
        }

        textMonitor.start()
        hotkeyManager.install()
        permissionGuide.showIfNeeded()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        textMonitor?.stop()
        if let obs = clarityObserver {
            NotificationCenter.default.removeObserver(obs)
            clarityObserver = nil
        }
        hotkeyManager?.uninstall()
    }
}
