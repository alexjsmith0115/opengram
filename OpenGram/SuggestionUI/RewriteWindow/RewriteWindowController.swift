import AppKit
import SwiftUI
import os.log

/// Single-shot controller. One `show()`, one teardown, then discard.
/// Spawning a new session requires a fresh instance from the coordinator.
/// Calling `show()` on a torn-down controller is a no-op (returns false).
@MainActor
final class RewriteWindowController {
    private static let logger = Log.logger(for: "RewriteWindowController")

    private let viewModel: RewriteWindowViewModel
    private let onApplyRequested: () -> Void
    private let onCancelRequested: () -> Void
    private let onOpenSettings: () -> Void

    private var panel: RewriteHostPanel?
    private weak var originalTextView: NSTextView?
    private weak var revisedTextView: NSTextView?
    private var keyMonitor: Any?
    private var clickOutsideLocalMonitor: Any?
    private var clickOutsideGlobalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private var focusRetryTask: Task<Void, Never>?

    /// Guards all late callbacks (mount callbacks, retry tasks). Flipped false by any teardown.
    private var isLive = true

    init(
        viewModel: RewriteWindowViewModel,
        onApply: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onApplyRequested = onApply
        self.onCancelRequested = onCancel
        self.onOpenSettings = onOpenSettings
    }

    /// Builds and presents the panel. Returns false and tears down if the panel
    /// fails to become key or focus assignment is exhausted after retries.
    @discardableResult
    func show(near bounds: CGRect?) -> Bool {
        guard isLive else {
            Self.logger.error("show() called on torn-down controller; ignoring")
            return false
        }

        let panel = RewriteHostPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320))
        self.panel = panel

        let view = RewriteWindowView(
            viewModel: viewModel,
            onApply: { [weak self] in self?.onApplyRequested() },
            onCancel: { [weak self] in self?.onCancelRequested() },
            onOpenSettings: { [weak self] in self?.onOpenSettings() },
            onOriginalMounted: { [weak self] tv in
                guard let self, self.isLive else { return }
                self.originalTextView = tv
                self.tryWireKeyViewLoop()
            },
            onRevisedMounted: { [weak self] tv in
                guard let self, self.isLive else { return }
                self.revisedTextView = tv
                self.tryWireKeyViewLoop()
            }
        )

        let host = NSHostingView(rootView: view)
        panel.contentView = host

        panel.onCommandReturn = { [weak self] in
            guard let self, self.viewModel.canApply else { return }
            self.onApplyRequested()
        }
        panel.onCancelOp = { [weak self] in self?.onCancelRequested() }

        positionPanel(panel, near: bounds)
        panel.makeKeyAndOrderFront(nil)

        guard panel.isKeyWindow else {
            Self.logger.error("Panel failed to become key window; tearing down")
            teardownForFailedShow()
            return false
        }

        installKeyMonitor()
        installClickOutsideMonitors()
        installDeactivationObserver()

        panel.contentView?.layoutSubtreeIfNeeded()
        if attemptFocusAssignment() { return true }

        focusRetryTask = Task { @MainActor [weak self] in
            await self?.deferredFocusRetry(maxAttempts: 5)
        }
        return true
    }

    /// User-facing dismissal path.
    func hide() { teardown() }

    /// Silent cleanup used when a hotkey re-fire replaces a visible session.
    func teardownForSessionReplacement() { teardown() }

    /// Silent cleanup used when `show()` fails partway through partial setup.
    func teardownForFailedShow() { teardown() }

    // MARK: - Private

    private func teardown() {
        guard isLive else { return }
        isLive = false
        focusRetryTask?.cancel()
        focusRetryTask = nil
        viewModel.cancel()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = clickOutsideLocalMonitor { NSEvent.removeMonitor(m); clickOutsideLocalMonitor = nil }
        if let m = clickOutsideGlobalMonitor { NSEvent.removeMonitor(m); clickOutsideGlobalMonitor = nil }
        if let obs = deactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            deactivationObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        originalTextView = nil
        revisedTextView = nil
    }

    private func attemptFocusAssignment() -> Bool {
        guard isLive, let panel, let tv = originalTextView else { return false }
        panel.makeFirstResponder(tv)
        return panel.firstResponder === tv
    }

    private func deferredFocusRetry(maxAttempts: Int) async {
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: .milliseconds(16))
            guard isLive, let panel else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            if attemptFocusAssignment() { return }
        }
        guard isLive else { return }
        Self.logger.error("Focus assignment exhausted retries; tearing down")
        teardownForFailedShow()
    }

    /// Idempotent — the assignment itself is the guard; no flag needed.
    private func tryWireKeyViewLoop() {
        guard let original = originalTextView, let revised = revisedTextView else { return }
        original.nextKeyView = revised
        revised.nextKeyView = original
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let panel = self.panel,
                  event.window === panel
            else { return event }

            if event.keyCode == 53 { // Esc
                if Self.hasMarkedText(in: panel) { return event } // let IME handle
                self.onCancelRequested()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "\r" {
                // Consume regardless; no-op when !canApply so ⌘↵ never leaks to target app.
                if self.viewModel.canApply { self.onApplyRequested() }
                return nil
            }

            return event
        }
    }

    private func installClickOutsideMonitors() {
        clickOutsideLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel { self.onCancelRequested() }
            return event
        }
        clickOutsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.onCancelRequested()
        }
    }

    private func installDeactivationObserver() {
        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onCancelRequested()
        }
    }

    private func positionPanel(_ panel: NSPanel, near bounds: CGRect?) {
        if let bounds,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(bounds) }) ?? NSScreen.main {
            let origin = PanelPositioner.origin(
                for: panel.frame.size,
                near: bounds,
                on: screen
            )
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            ))
        }
    }

    /// Returns true if the current first responder is composing via an input method.
    private static func hasMarkedText(in window: NSWindow) -> Bool {
        guard let client = window.firstResponder as? NSTextInputClient else { return false }
        return client.hasMarkedText()
    }
}
