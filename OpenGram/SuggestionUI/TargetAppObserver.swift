@preconcurrency import ApplicationServices
import Foundation

/// Watches a target application via AXObserver and fires a dismiss callback
/// when the window moves, resizes, focus changes, or the app deactivates.
///
/// The dismiss callback runs on the main actor. Designed for one active observer
/// at a time — install() implicitly uninstalls any prior observer.
final class TargetAppObserver {
    private var axObserver: AXObserver?
    private var dismissContext: DismissContext?

    func install(pid: pid_t, onDismiss: @escaping @MainActor () -> Void) {
        uninstall()

        let context = DismissContext(handler: onDismiss)
        self.dismissContext = context
        let ptr = Unmanaged.passRetained(context).toOpaque()

        var observer: AXObserver?
        AXObserverCreate(pid, { _, _, _, userData in
            guard let userData else { return }
            let ctx = Unmanaged<DismissContext>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ctx.handler()
                }
            }
        }, &observer)

        guard let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let notifications: [String] = [
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXFocusedUIElementChangedNotification,
            kAXApplicationDeactivatedNotification,
        ]
        for notification in notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, ptr)
        }

        CFRunLoopAddSource(
            RunLoop.main.getCFRunLoop(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        self.axObserver = observer
    }

    func uninstall() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                RunLoop.main.getCFRunLoop(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
            axObserver = nil
        }
        if let context = dismissContext {
            Unmanaged.passRetained(context).release()
            dismissContext = nil
        }
    }

    deinit {
        // Safety net: clean up if caller forgot to uninstall
        if axObserver != nil {
            uninstall()
        }
    }
}

// MARK: - Private

// @unchecked Sendable: handler is always dispatched onto the main actor,
// so concurrent access to the stored closure is not possible at runtime.
private final class DismissContext: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }
}
