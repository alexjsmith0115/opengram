import AppKit
import QuartzCore

/// Drives a CADisplayLink pump during active scroll (PERF-09).
///
/// Caller pings `noteScrollEvent()` on every scroll event (NSEvent.scrollWheel
/// or AX kAXScrolledVisibleChildrenChangedNotification). Tracker lazy-installs
/// its display link on the first ping, fires `onTick` once per refresh while
/// events keep arriving, and fires `onIdle` exactly once after `idleTimeout`
/// elapses without a new event — then self-stops.
@MainActor
final class ScrollTracker {

    private weak var hostView: NSView?
    var displayLink: CADisplayLink?
    private var lastEventTime: CFTimeInterval = 0
    private let idleTimeout: CFTimeInterval

    /// Fires once per display refresh while the pump is active.
    var onTick: (@MainActor () -> Void)?

    /// Fires exactly once after `idleTimeout` seconds with no new events.
    /// Pump stops before this fires.
    var onIdle: (@MainActor () -> Void)?

    init(hostView: NSView, idleTimeout: CFTimeInterval = 0.18) {
        self.hostView = hostView
        self.idleTimeout = idleTimeout
    }

    /// Called for every scroll event. Starts the display link on first event;
    /// refreshes the idle timer on subsequent events.
    func noteScrollEvent() {
        lastEventTime = CACurrentMediaTime()
        guard displayLink == nil, let hostView else { return }
        let link = hostView.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        onTick?()
        if CACurrentMediaTime() - lastEventTime > idleTimeout {
            stop()
            onIdle?()
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        MainActor.assumeIsolated {
            displayLink?.invalidate()
        }
    }
}
