import Testing
import AppKit
import QuartzCore
@testable import OpenGramLib

/// Shared host window for the suite. Creating + ordering multiple NSWindows
/// across sequential tests races the WindowServer (NSCGS pre-commit fence
/// errors followed by a process restart). Reusing one window orderedFront
/// once avoids the crash and keeps every CADisplayLink screen-bound.
@MainActor
private enum SharedHost {
    static let window: NSWindow = {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        w.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        w.orderFrontRegardless()
        return w
    }()
}

@Suite("ScrollTracker", .serialized)
@MainActor
struct ScrollTrackerTests {

    /// Returns a fresh subview of the shared host window so each test gets an
    /// isolated NSView while still inheriting the window's screen binding.
    private func makeHostedView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        SharedHost.window.contentView?.addSubview(view)
        return view
    }

    /// Pumps the main run loop for the given interval so CADisplayLink has
    /// a chance to fire. `Task.sleep` alone does not drive the NSRunLoop
    /// inside a test-host process, so timer-based callbacks never arrive.
    private func pumpMainRunLoop(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    @Test("onTick fires at least once while noteScrollEvent is called periodically")
    func ticksWhileActive() {
        let view = makeHostedView()
        let tracker = ScrollTracker(hostView: view, idleTimeout: 0.5)
        var ticks = 0
        tracker.onTick = { ticks += 1 }
        tracker.noteScrollEvent()
        pumpMainRunLoop(for: 0.1)
        tracker.noteScrollEvent()
        pumpMainRunLoop(for: 0.1)
        #expect(ticks > 0)
        tracker.stop()
    }

    @Test("onIdle fires exactly once after idleTimeout elapses with no new events")
    func idleFires() {
        let view = makeHostedView()
        let tracker = ScrollTracker(hostView: view, idleTimeout: 0.05)
        var idleCount = 0
        tracker.onIdle = { idleCount += 1 }
        tracker.noteScrollEvent()
        pumpMainRunLoop(for: 0.25)
        #expect(idleCount == 1)
    }

    @Test("stop() invalidates the display link")
    func stopInvalidates() {
        let view = makeHostedView()
        let tracker = ScrollTracker(hostView: view, idleTimeout: 1.0)
        tracker.noteScrollEvent()
        #expect(tracker.displayLink != nil)
        tracker.stop()
        #expect(tracker.displayLink == nil)
    }
}
