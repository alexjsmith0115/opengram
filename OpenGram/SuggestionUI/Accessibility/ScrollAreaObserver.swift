@preconcurrency import ApplicationServices
import Foundation

/// Observes a single AX scroll-area element for programmatic scrolls (PERF-11).
///
/// Catches arrow-key scrolls, find-navigation, and `scrollToVisible:` — all of
/// which fire `kAXScrolledVisibleChildrenChangedNotification` but do NOT fire
/// NSEvent.scrollWheel. Mirrors TargetAppObserver's retain/release discipline.
///
/// One observer at a time; install() implicitly uninstalls any prior observer.
@MainActor
final class ScrollAreaObserver {
    /// Apple documents the notification key as the bare string
    /// `"AXScrolledVisibleChildrenChanged"`. The Swift overlay does not export a
    /// named constant, so we use the documented literal directly.
    private static let scrolledVisibleChildrenChangedNotification: CFString =
        "AXScrolledVisibleChildrenChanged" as CFString

    private var axObserver: AXObserver?
    private var scrollContext: ScrollContext?
    /// Stores the Unmanaged reference from passRetained so we release the SAME
    /// retain we created — never call passRetained a second time.
    private var unmanagedContext: Unmanaged<ScrollContext>?

    func install(
        pid: pid_t,
        element: AXUIElement,
        onScrollChanged: @escaping @MainActor () -> Void
    ) {
        uninstall()

        let context = ScrollContext(handler: onScrollChanged)
        self.scrollContext = context
        let unmanaged = Unmanaged.passRetained(context)
        self.unmanagedContext = unmanaged
        let ptr = unmanaged.toOpaque()

        var observer: AXObserver?
        AXObserverCreate(pid, { _, _, _, userData in
            guard let userData else { return }
            let ctx = Unmanaged<ScrollContext>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                ctx.handler()
            }
        }, &observer)

        guard let observer else { return }

        AXObserverAddNotification(
            observer,
            element,
            Self.scrolledVisibleChildrenChangedNotification,
            ptr
        )

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
        if let unmanaged = unmanagedContext {
            unmanaged.release()
            unmanagedContext = nil
        }
        scrollContext = nil
    }
}

// MARK: - Private

// @unchecked Sendable: handler is always dispatched onto the main actor,
// so concurrent access to the stored closure is not possible at runtime.
private final class ScrollContext: @unchecked Sendable {
    let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }
}
