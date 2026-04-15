@preconcurrency import ApplicationServices
import AppKit
import Foundation

/// Hybrid text monitor that registers AXObserver for kAXValueChangedNotification on the
/// focused text element, with automatic fallback to 1-second polling for apps that don't
/// fire AX notifications reliably (D-01, D-02, D-03).
///
/// Lifecycle: call `start()` once on launch (D-07: always-on). Call `stop()` on termination.
/// Wire `onCheckComplete` and `onDismiss` before calling `start()`.
@MainActor
final class TextMonitor {

    // MARK: - Dependencies

    private let textEngine: any AXTextEngineProtocol
    private let harperService: any GrammarCheckerProtocol
    private let capabilityCache: any AXCapabilityCacheProtocol
    private let quirksTable: AppQuirksTable
    private let watchdog: AXCallWatchdog

    // MARK: - Callbacks

    /// Called when a grammar check completes. Receives the suggestions and the TextContext
    /// that was checked.
    var onCheckComplete: ((@MainActor ([Suggestion], TextContext) -> Void))?

    /// Called when monitoring pauses: app switch to a non-text app, or non-text element focused.
    var onDismiss: ((@MainActor () -> Void))?

    // MARK: - Internal state

    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var observedBundleID: String?

    private var debounceWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var lastKnownText: String?

    // Track whether an AX notification fired since the last poll tick, used to detect
    // apps that silently drop kAXValueChangedNotification (D-02 runtime detection).
    private var notificationFiredSinceLastPoll: Bool = false

    // Counts consecutive poll ticks where a notification fired and text changed,
    // used to promote an app to notification-reliable and stop the poll timer.
    private var consecutiveNotificationHits: Int = 0
    private let reliabilityThreshold = 5

    private var appSwitchObserver: NSObjectProtocol?
    private var appSwitchDebounce: DispatchWorkItem?
    private var checkTask: Task<Void, Never>?

    // Retains the MonitorContext passed to the AX callback via Unmanaged.
    private var unmanagedContext: Unmanaged<MonitorContext>?

    // MARK: - Init

    init(
        textEngine: any AXTextEngineProtocol,
        harperService: any GrammarCheckerProtocol,
        capabilityCache: any AXCapabilityCacheProtocol,
        quirksTable: AppQuirksTable = .shared,
        watchdog: AXCallWatchdog = .shared
    ) {
        self.textEngine = textEngine
        self.harperService = harperService
        self.capabilityCache = capabilityCache
        self.quirksTable = quirksTable
        self.watchdog = watchdog
    }

    // MARK: - Public API

    /// Starts always-on monitoring. Subscribes to app-activation notifications and installs
    /// an AXObserver on the current frontmost text field.
    func start() {
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

    /// Stops monitoring: removes the workspace observer, uninstalls the AXObserver,
    /// cancels debounce and any in-flight check task.
    func stop() {
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

        let pid = app.processIdentifier

        // Read the focused element from the system-wide accessibility element.
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

        // Per D-11: respect the watchdog blocklist before installing AX observer.
        if watchdog.shouldSkip(for: bundleID) { return }

        installObserver(pid: pid, element: element, bundleID: bundleID)
    }

    private func installObserver(pid: pid_t, element: AXUIElement, bundleID: String) {
        uninstallCurrentObserver()

        let context = MonitorContext { [weak self] notificationName in
            guard let self else { return }
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

        // Register on the text element for value changes (D-04: value only, not selection).
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, ptr)
        // Register on the app element for field switches within the same app (D-09).
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
        notificationFiredSinceLastPoll = false
        consecutiveNotificationHits = 0
    }

    // MARK: - Notification handling

    private func handleValueChanged() {
        notificationFiredSinceLastPoll = true
        scheduleDebounce()
    }

    // MARK: - Debounce

    func scheduleDebounce() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.runCheck()
        }
        debounceWork = work
        // D-05: 800ms debounce to avoid checking mid-word.
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
            // Focus moved to a different element — reinstall observer on the new field.
            installOnFocusedElement()
            return
        }

        guard let context = textEngine.extractText(), !context.text.isEmpty else { return }

        checkTask?.cancel()
        checkTask = Task {
            let suggestions = await harperService.check(text: context.text)
            guard !Task.isCancelled else { return }
            self.onCheckComplete?(suggestions, context)
        }
    }

    // MARK: - Poll timer

    private func startPollTimer() {
        stopPollTimer()
        // D-03: 1-second poll interval for fallback mode.
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

        // T-07-03: respect watchdog blocklist — never make AX calls on a blocklisted app.
        if watchdog.shouldSkip(for: bundleID) {
            // Do NOT reset notificationFiredSinceLastPoll; the missed notification detection
            // must not fire during watchdog suppression (Pitfall 3).
            return
        }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        guard result == .success,
              let valueRef,
              CFGetTypeID(valueRef) == CFStringGetTypeID() else {
            notificationFiredSinceLastPoll = false
            return
        }

        let currentText = valueRef as! String
        let textChanged = currentText != lastKnownText

        if textChanged {
            if !notificationFiredSinceLastPoll {
                // Poll detected a change that no AX notification fired for — mark as unreliable.
                capabilityCache.storeNotificationReliability(bundleID: bundleID, reliable: false)
                consecutiveNotificationHits = 0
            } else {
                // Notification fired and poll confirmed the change — count toward reliability.
                consecutiveNotificationHits += 1
                if consecutiveNotificationHits >= reliabilityThreshold {
                    capabilityCache.storeNotificationReliability(bundleID: bundleID, reliable: true)
                    stopPollTimer()
                }
            }
            lastKnownText = currentText
            scheduleDebounce()
        }

        notificationFiredSinceLastPoll = false
    }

    // MARK: - App switch handling

    private func handleAppActivation(_ app: NSRunningApplication) {
        appSwitchDebounce?.cancel()

        // T-07-05: 100ms debounce prevents registering/unregistering observers for
        // transient intermediate apps during rapid Cmd-Tab switching.
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

    /// Returns true only for element roles that accept keyboard text input.
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
