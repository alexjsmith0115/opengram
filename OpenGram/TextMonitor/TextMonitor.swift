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
    private let store: ParagraphSuggestionStore?
    private let splitter: ParagraphSplitter?
    private let textBoxWriter: (@Sendable (String, String) -> Void)?
    private let config: OpenGramConfig?

    // MARK: - Callbacks

    var onCheckComplete: ((@MainActor ([Suggestion], TextContext) -> Void))?
    var onLLMFinished: ((@MainActor () -> Void))?
    var onDismiss: ((@MainActor () -> Void))?
    /// FR-18 edit-closes hook. Fires synchronously on every AX value-change
    /// notification BEFORE the 0.8s debounce, so subscribers (e.g., RephraseCardPanelController)
    /// can close transient UI on the user's first keystroke without waiting for the check cycle.
    /// Sole subscriber today; if a second subscriber appears later, refactor to multicast.
    var onKeystroke: ((@MainActor () -> Void))?

    // MARK: - Config (set by AppDelegate at init)

    var appWhitelist = AppWhitelist()

    // MARK: - Internal state

    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var observedBundleID: String?

    private var debounceWork: DispatchWorkItem?
    /// Separate work item for the LLM reconcile debounce. Harper debounce (`debounceWork`)
    /// runs on its own cadence at ~800ms; LLM reconcile runs at `config.llmDebounceMs`
    /// (default 2000ms) so typing storms don't burn LLM calls mid-edit.
    private var llmReconcileWork: DispatchWorkItem?
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
        watchdog: AXCallWatchdog = .shared,
        store: ParagraphSuggestionStore? = nil,
        splitter: ParagraphSplitter? = nil,
        textBoxWriter: (@Sendable (String, String) -> Void)? = nil,
        config: OpenGramConfig? = nil
    ) {
        self.textEngine = textEngine
        self.orchestrator = orchestrator
        self.capabilityCache = capabilityCache
        self.quirksTable = quirksTable
        self.watchdog = watchdog
        self.store = store
        self.splitter = splitter
        self.textBoxWriter = textBoxWriter
        self.config = config
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
        llmReconcileWork?.cancel()
        llmReconcileWork = nil
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
              let bundleID = app.bundleIdentifier else {
            Self.logger.warning("installOnFocusedElement aborted: no frontmost app or bundle ID")
            return
        }

        Self.logger.info("installOnFocusedElement frontmost name=\(app.localizedName ?? "nil", privacy: .public) bundle=\(bundleID, privacy: .public) pid=\(app.processIdentifier)")

        guard appWhitelist.isAllowed(bundleID) else {
            Self.logger.info("installOnFocusedElement blocked: bundle not whitelisted \(bundleID, privacy: .public)")
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
            Self.logger.warning("installOnFocusedElement aborted: focused element read err=\(result.rawValue)")
            onDismiss?()
            return
        }
        let element = focusedRef as! AXUIElement

        guard isTextElement(element) else {
            Self.logger.info("installOnFocusedElement blocked: focused role is not text-capable bundle=\(bundleID, privacy: .public)")
            onDismiss?()
            return
        }

        if watchdog.shouldSkip(for: bundleID) {
            Self.logger.warning("installOnFocusedElement aborted: AX watchdog is skipping bundle=\(bundleID, privacy: .public)")
            return
        }

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
        Self.logger.info("installObserver installed pid=\(pid) bundle=\(bundleID, privacy: .public)")

        // Capture current text as baseline for polling diff.
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let valueRef, CFGetTypeID(valueRef) == CFStringGetTypeID() {
            lastKnownText = (valueRef as! String)
            Self.logger.info("installObserver baseline value len=\((valueRef as! String).count) sample=\(Self.sample(valueRef as! String), privacy: .public)")
        } else {
            Self.logger.info("installObserver baseline value unavailable bundle=\(bundleID, privacy: .public)")
        }

        // Decide whether to start poll timer: pre-classified unreliable OR unknown (D-02).
        let preClassified = quirksTable.quirk(for: bundleID)?.notificationUnreliable == true
        let runtimeKnownUnreliable = capabilityCache.isNotificationReliable(bundleID: bundleID) == false
        let reliabilityUnknown = capabilityCache.isNotificationReliable(bundleID: bundleID) == nil

        if preClassified || runtimeKnownUnreliable || reliabilityUnknown {
            Self.logger.info("installObserver starting poll timer bundle=\(bundleID, privacy: .public) preClassified=\(preClassified) runtimeKnownUnreliable=\(runtimeKnownUnreliable) reliabilityUnknown=\(reliabilityUnknown)")
            startPollTimer()
        } else {
            Self.logger.info("installObserver using AX notifications only bundle=\(bundleID, privacy: .public)")
        }

        // PLL-09: eager reconcile on focus install.
        driveStoreReconcile()
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
        llmReconcileWork?.cancel()
        llmReconcileWork = nil
        observedElement = nil
        observedPID = nil
        observedBundleID = nil
        reliabilityDetector.reset()
    }

    // MARK: - Notification handling

    func handleValueChanged() {
        Self.logger.info("handleValueChanged bundle=\(self.observedBundleID ?? "nil", privacy: .public)")
        reliabilityDetector.recordNotification()
        onKeystroke?()
        scheduleDebounce()
        driveStoreOnValueChange()
        scheduleLLMReconcile()
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
        guard let observedElement else {
            Self.logger.info("runCheck skipped: no observed element")
            return
        }

        // Verify the *same* element is still focused before extracting text (Pitfall 5 guard).
        let systemWide = AXUIElementCreateSystemWide()
        var currentFocusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &currentFocusRef
        ) == .success else {
            Self.logger.warning("runCheck skipped: focused element read failed")
            return
        }

        let currentElement = currentFocusRef as! AXUIElement
        guard CFEqual(currentElement, observedElement) else {
            Self.logger.info("runCheck focus changed: reinstalling focused element")
            installOnFocusedElement()
            return
        }

        guard let context = textEngine.extractText(), !context.text.isEmpty else {
            Self.logger.warning("runCheck skipped: extractText returned nil or empty")
            return
        }
        Self.logger.info("runCheck extracted bundle=\(context.bundleID, privacy: .public) len=\(context.text.count) sample=\(Self.sample(context.text), privacy: .public)")

        checkTask?.cancel()
        checkTask = Task {
            await orchestrator.runCheck(
                text: context.text,
                context: context,
                onHarperComplete: { [weak self] suggestions, ctx in
                    guard let self, !Task.isCancelled else { return }
                    self.onCheckComplete?(suggestions, ctx)
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
              let bundleID = observedBundleID else {
            Self.logger.info("pollForChanges skipped: no observed element/bundle")
            return
        }

        if watchdog.shouldSkip(for: bundleID) {
            Self.logger.warning("pollForChanges skipped: AX watchdog is skipping bundle=\(bundleID, privacy: .public)")
            return
        }

        // Validate element is still focused before AX call (F-10 fix).
        let systemWide = AXUIElementCreateSystemWide()
        var focusRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusRef
        ) == .success, let focusRef {
            let focused = focusRef as! AXUIElement
            guard CFEqual(focused, element) else {
                Self.logger.info("pollForChanges focus changed: reinstalling focused element")
                installOnFocusedElement()
                return
            }
        }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        guard result == .success,
              let valueRef,
              CFGetTypeID(valueRef) == CFStringGetTypeID() else {
            Self.logger.warning("pollForChanges value read failed bundle=\(bundleID, privacy: .public) err=\(result.rawValue) cast=\(valueRef.map { CFGetTypeID($0) == CFStringGetTypeID() } ?? false)")
            reliabilityDetector.reset()
            return
        }

        let currentText = valueRef as! String
        let textChanged = currentText != lastKnownText
        Self.logger.info("pollForChanges bundle=\(bundleID, privacy: .public) textChanged=\(textChanged) len=\(currentText.count) sample=\(Self.sample(currentText), privacy: .public)")

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
            Self.logger.info("app activated name=\(app.localizedName ?? "nil", privacy: .public) bundle=\(newBundleID ?? "nil", privacy: .public) pid=\(app.processIdentifier)")
            if newBundleID == self.observedBundleID { return }
            self.uninstallCurrentObserver()
            self.onDismiss?()
            self.installOnFocusedElement()
        }
        appSwitchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    // MARK: - Store integration (D-03: reuse existing AX observer)

    /// Debounced LLM reconcile driver. Keystrokes schedule this; each fresh keystroke
    /// cancels and re-schedules. Delay resolved live from `config.llmDebounceMs` so
    /// a Settings write takes effect on the next typing pause without relaunch.
    /// A nil config (tests without full wiring) disables the debounce entirely.
    @MainActor
    private func scheduleLLMReconcile() {
        guard store != nil, splitter != nil else { return }
        let delayMs = config?.llmDebounceMs ?? OpenGramConfig.defaultLLMDebounceMs
        llmReconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.driveStoreReconcile()
        }
        llmReconcileWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(delayMs),
            execute: work
        )
    }

    /// Fires reconcile immediately, cancelling any pending debounced work. Used by the
    /// hotkey path so users can force a fresh LLM pass without waiting out the debounce.
    @MainActor
    func reconcileNow() {
        llmReconcileWork?.cancel()
        llmReconcileWork = nil
        driveStoreReconcile()
    }

    /// PLL-04: keystroke → `store.invalidateDisplayed` for instant underline invalidation.
    /// LLM reconciliation is scheduled separately via `scheduleLLMReconcile()` so the
    /// invalidate path stays synchronous and never fires queue submits.
    /// Caret offset is resolved from `TextContext.selectionRange.location` so the splitter
    /// identifies the caret paragraph correctly even on value-change ticks (PLL-06).
    @MainActor
    private func driveStoreOnValueChange() {
        guard let store, let splitter else { return }
        guard let context = textEngine.extractText(), !context.text.isEmpty else {
            Self.logger.warning("driveStoreOnValueChange skipped: extractText returned nil or empty")
            return
        }
        let bundleID = context.bundleID
        let text = context.text
        let caretOffset: Int? = context.selectionRange.map { Int($0.location) }
        textBoxWriter?(bundleID, text)
        let set = splitter.split(text: text, bundleID: bundleID, version: nil, caretOffset: caretOffset)
        Task { [store] in
            await store.invalidateDisplayed(bundleID: bundleID, currentSet: set)
        }
    }

    /// Fires `store.reconcile`, submitting LLM requests for every non-caret, above-threshold
    /// paragraph that isn't already cached. Called on:
    ///   - Focus change (PLL-09 eager reconcile on new element)
    ///   - Keystroke debounce tick (`scheduleLLMReconcile` after `llmDebounceMs`)
    ///   - Hotkey (`reconcileNow` — bypasses debounce)
    /// Caret offset resolved from `TextContext.selectionRange.location` so PLL-06
    /// caret-paragraph skip is honored.
    @MainActor
    private func driveStoreReconcile() {
        guard let store, let splitter else { return }
        guard let context = textEngine.extractText(), !context.text.isEmpty else {
            Self.logger.warning("driveStoreReconcile skipped: extractText returned nil or empty")
            return
        }
        let bundleID = context.bundleID
        let text = context.text
        let caretOffset: Int? = context.selectionRange.map { Int($0.location) }
        textBoxWriter?(bundleID, text)
        let set = splitter.split(text: text, bundleID: bundleID, version: nil, caretOffset: caretOffset)
        Task { [store] in
            await store.reconcile(set: set)
        }
    }

#if DEBUG
    // MARK: - Test seam (DEBUG only)

    /// Invokes the eager reconcile path as if the focused element had just
    /// been installed. Test-only — production callers use the real AX focus-change
    /// notification path which fires `driveStoreOnFocusChange` from `installObserver`.
    /// Guarded by `#if DEBUG` so release builds cannot invoke this.
    func triggerEagerReconcileForTesting() {
        driveStoreReconcile()
    }
#endif

    // MARK: - Role validation

    func isTextElement(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleRef,
              CFGetTypeID(roleRef) == CFStringGetTypeID() else {
            Self.logger.info("isTextElement false: role unavailable")
            return false
        }

        let role = roleRef as! String
        let supported = Self.supportsTextRole(role)
        Self.logger.info("isTextElement role=\(role, privacy: .public) supported=\(supported)")
        return supported
    }

    static func supportsTextRole(_ role: String) -> Bool {
        role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String
            || role == "AXWebArea"
    }

    private static func sample(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return String(oneLine.prefix(160))
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
