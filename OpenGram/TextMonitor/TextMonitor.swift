@preconcurrency import ApplicationServices
import AppKit
import Foundation
import os.log

/// Hybrid text monitor that registers AXObserver for kAXValueChangedNotification on the
/// focused text element, with automatic fallback to 1-second polling for apps that don't
/// fire AX notifications reliably (D-01, D-02, D-03).
///
/// Lifecycle: call `start()` once on launch (D-07: always-on). Call `stop()` on termination.
/// Wire `onCheckComplete` and `onDismiss` before calling `start()`.
@MainActor
final class TextMonitor {

    private static let logger = Log.logger(for: "TextMonitor")

    // MARK: - Dependencies

    private let textEngine: any AXTextEngineProtocol
    private let orchestrator: CheckOrchestrator
    private let capabilityCache: any AXCapabilityCacheProtocol
    private let quirksTable: AppQuirksTable
    private let watchdog: AXCallWatchdog

    // MARK: - Callbacks

    var onCheckComplete: ((@MainActor ([Suggestion], TextContext) -> Void))?
    var onLLMBatch: ((@MainActor ([LLMStyleSuggestion], TextContext) -> Void))?
    var onLLMFinished: ((@MainActor () -> Void))?
    var onDismiss: ((@MainActor () -> Void))?
    /// Phase 18 FR-18 edit-closes hook. Fires synchronously on every AX value-change
    /// notification BEFORE the 0.8s debounce, so subscribers (e.g., RephraseCardPanelController)
    /// can close transient UI on the user's first keystroke without waiting for the check cycle.
    /// Sole subscriber as of Phase 18; if a second subscriber appears later, refactor to multicast.
    var onKeystroke: ((@MainActor () -> Void))?

    // MARK: - Config (set by AppDelegate at init)

    var appWhitelist = AppWhitelist()
    var llmConfig: LLMConfig = .default
    var llmAPIKey: String?

    // MARK: - Internal state

    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var observedBundleID: String?

    private var debounceWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var lastKnownText: String?
    private var reliabilityDetector = ReliabilityDetector()

    private var appSwitchObserver: NSObjectProtocol?
    private var appSwitchDebounce: DispatchWorkItem?
    private var checkTask: Task<Void, Never>?

    private var unmanagedContext: Unmanaged<MonitorContext>?
    /// Set to true on stop() — checked inside C callback to prevent UAF.
    private var stopped = false

    // MARK: - Init

    init(
        textEngine: any AXTextEngineProtocol,
        orchestrator: CheckOrchestrator,
        capabilityCache: any AXCapabilityCacheProtocol,
        quirksTable: AppQuirksTable = .shared,
        watchdog: AXCallWatchdog = .shared
    ) {
        self.textEngine = textEngine
        self.orchestrator = orchestrator
        self.capabilityCache = capabilityCache
        self.quirksTable = quirksTable
        self.watchdog = watchdog
    }

    // MARK: - Public API

    func start() {
        stopped = false
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.handleAppActivation(app)
            }
        }

        installOnFocusedElement()
    }

    func stop() {
        stopped = true
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
        appSwitchDebounce?.cancel()
        appSwitchDebounce = nil
        checkTask?.cancel()
        checkTask = nil
        uninstallCurrentObserver()
    }

    /// Cancels the pending debounce and runs a grammar check immediately (D-14: hotkey bypass).
    func forceCheckNow() {
        debounceWork?.cancel()
        debounceWork = nil
        checkTask?.cancel()
        checkTask = nil
        runCheck()
    }

    // MARK: - Observer installation

    private func installOnFocusedElement() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }

        guard appWhitelist.isAllowed(bundleID) else {
            onDismiss?()
            return
        }

        let pid = app.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard result == .success, let focusedRef else {
            onDismiss?()
            return
        }
        let element = focusedRef as! AXUIElement

        guard isTextElement(element) else {
            onDismiss?()
            return
        }

        if watchdog.shouldSkip(for: bundleID) { return }

        installObserver(pid: pid, element: element, bundleID: bundleID)
    }

    private func installObserver(pid: pid_t, element: AXUIElement, bundleID: String) {
        uninstallCurrentObserver()

        let context = MonitorContext { [weak self] notificationName in
            guard let self, !self.stopped else { return }
            if notificationName == kAXValueChangedNotification as String {
                self.handleValueChanged()
            } else if notificationName == kAXFocusedUIElementChangedNotification as String {
                self.installOnFocusedElement()
            }
        }

        let unmanaged = Unmanaged.passRetained(context)
        self.unmanagedContext = unmanaged
        let ptr = unmanaged.toOpaque()

        var observer: AXObserver?
        AXObserverCreate(pid, { _, _, notificationName, userData in
            guard let userData else { return }
            let ctx = Unmanaged<MonitorContext>.fromOpaque(userData).takeUnretainedValue()
            let name = notificationName as String
            Task { @MainActor in
                ctx.handler(name)
            }
        }, &observer)

        guard let observer else {
            unmanaged.release()
            self.unmanagedContext = nil
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, ptr)
        AXObserverAddNotification(
            observer, appElement, kAXFocusedUIElementChangedNotification as CFString, ptr
        )

        CFRunLoopAddSource(
            RunLoop.main.getCFRunLoop(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        self.axObserver = observer
        self.observedElement = element
        self.observedPID = pid
        self.observedBundleID = bundleID

        // Capture current text as baseline for polling diff.
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let valueRef, CFGetTypeID(valueRef) == CFStringGetTypeID() {
            lastKnownText = (valueRef as! String)
        }

        // Decide whether to start poll timer: pre-classified unreliable OR unknown (D-02).
        let preClassified = quirksTable.quirk(for: bundleID)?.notificationUnreliable == true
        let runtimeKnownUnreliable = capabilityCache.isNotificationReliable(bundleID: bundleID) == false
        let reliabilityUnknown = capabilityCache.isNotificationReliable(bundleID: bundleID) == nil

        if preClassified || runtimeKnownUnreliable || reliabilityUnknown {
            startPollTimer()
        }
    }

    private func uninstallCurrentObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                RunLoop.main.getCFRunLoop(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            axObserver = nil
        }
        if let unmanaged = unmanagedContext {
            unmanaged.release()
            unmanagedContext = nil
        }
        stopPollTimer()
        debounceWork?.cancel()
        debounceWork = nil
        observedElement = nil
        observedPID = nil
        observedBundleID = nil
        reliabilityDetector.reset()
    }

    // MARK: - Notification handling

    func handleValueChanged() {
        reliabilityDetector.recordNotification()
        onKeystroke?()
        scheduleDebounce()
    }

    // MARK: - Debounce

    func scheduleDebounce() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runCheck()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Grammar check

    private func runCheck() {
        guard let observedElement else { return }

        // Verify the *same* element is still focused before extracting text (Pitfall 5 guard).
        let systemWide = AXUIElementCreateSystemWide()
        var currentFocusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &currentFocusRef
        ) == .success else { return }

        let currentElement = currentFocusRef as! AXUIElement
        guard CFEqual(currentElement, observedElement) else {
            installOnFocusedElement()
            return
        }

        guard let context = textEngine.extractText(), !context.text.isEmpty else { return }

        checkTask?.cancel()
        let config = llmConfig
        let apiKey = llmAPIKey
        checkTask = Task {
            await orchestrator.runCheck(
                text: context.text,
                context: context,
                config: config,
                apiKey: apiKey,
                onHarperComplete: { [weak self] suggestions, ctx in
                    guard let self, !Task.isCancelled else { return }
                    self.onCheckComplete?(suggestions, ctx)
                },
                onLLMBatch: { [weak self] suggestions, ctx in
                    guard let self, !Task.isCancelled else { return }
                    self.onLLMBatch?(suggestions, ctx)
                },
                onLLMFinished: { [weak self] in
                    guard self != nil, !Task.isCancelled else { return }
                    self?.onLLMFinished?()
                }
            )
        }
    }

    // MARK: - Poll timer

    private func startPollTimer() {
        stopPollTimer()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollForChanges()
            }
        }
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollForChanges() {
        guard let element = observedElement,
              let bundleID = observedBundleID else { return }

        if watchdog.shouldSkip(for: bundleID) { return }

        // Validate element is still focused before AX call (F-10 fix).
        let systemWide = AXUIElementCreateSystemWide()
        var focusRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusRef
        ) == .success, let focusRef {
            let focused = focusRef as! AXUIElement
            guard CFEqual(focused, element) else {
                installOnFocusedElement()
                return
            }
        }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        guard result == .success,
              let valueRef,
              CFGetTypeID(valueRef) == CFStringGetTypeID() else {
            reliabilityDetector.reset()
            return
        }

        let currentText = valueRef as! String
        let textChanged = currentText != lastKnownText

        let verdict = reliabilityDetector.evaluatePollTick(textChanged: textChanged)

        switch verdict {
        case .markedUnreliable:
            capabilityCache.storeNotificationReliability(bundleID: bundleID, reliable: false)
        case .promoted:
            capabilityCache.storeNotificationReliability(bundleID: bundleID, reliable: true)
            stopPollTimer()
        case .noChange:
            break
        }

        if textChanged {
            lastKnownText = currentText
            scheduleDebounce()
        }
    }

    // MARK: - App switch handling

    private func handleAppActivation(_ app: NSRunningApplication) {
        appSwitchDebounce?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let newBundleID = app.bundleIdentifier
            if newBundleID == self.observedBundleID { return }
            self.uninstallCurrentObserver()
            self.onDismiss?()
            self.installOnFocusedElement()
        }
        appSwitchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Role validation

    func isTextElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleRef,
              CFGetTypeID(roleRef) == CFStringGetTypeID() else { return false }

        let role = roleRef as! String
        return role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String
    }
}

// MARK: - MonitorContext

// @unchecked Sendable: handler is always dispatched onto the main actor,
// so concurrent access to the stored closure is not possible at runtime.
private final class MonitorContext: @unchecked Sendable {
    let handler: @MainActor (String) -> Void

    init(handler: @escaping @MainActor (String) -> Void) {
        self.handler = handler
    }
}
