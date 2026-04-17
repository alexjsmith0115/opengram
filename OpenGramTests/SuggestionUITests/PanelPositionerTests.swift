import Testing
import AppKit

@testable import OpenGramLib

@Suite("PanelPositioner margin placement")
@MainActor
struct PanelPositionerTests {

    private var screen: NSScreen { NSScreen.screens[0] }

    // MARK: - marginOrigin

    @Test("prefers right margin when space available")
    func rightMarginWhenSpaceAvailable() {
        let anchor = NSRect(x: 100, y: 300, width: 400, height: 200)
        let size = NSSize(width: 300, height: 150)
        let origin = PanelPositioner.marginOrigin(for: size, near: anchor, on: screen, gap: 8)

        #expect(origin.x == anchor.maxX + 8)
    }

    @Test("falls back to left margin when right overflows")
    func leftMarginWhenRightOverflows() {
        let visibleFrame = screen.visibleFrame
        // Anchor flush against right edge — no room on right
        let anchor = NSRect(x: visibleFrame.maxX - 200, y: 300, width: 200, height: 200)
        let size = NSSize(width: 300, height: 150)
        let origin = PanelPositioner.marginOrigin(for: size, near: anchor, on: screen, gap: 8)

        #expect(origin.x == anchor.minX - size.width - 8)
    }

    @Test("falls back to above/below when neither margin fits")
    func aboveBelowWhenNoMarginSpace() {
        let visibleFrame = screen.visibleFrame
        // Anchor spans nearly full screen width — no margin space
        let anchor = NSRect(x: visibleFrame.minX, y: 300, width: visibleFrame.width, height: 200)
        let size = NSSize(width: 300, height: 150)
        let origin = PanelPositioner.marginOrigin(for: size, near: anchor, on: screen, gap: 8)

        // Should match regular origin() result
        let fallback = PanelPositioner.origin(for: size, near: anchor, on: screen, gap: 8)
        #expect(origin == fallback)
    }

    @Test("vertically centers panel against anchor")
    func verticallyCentered() {
        let anchor = NSRect(x: 100, y: 300, width: 400, height: 200)
        let size = NSSize(width: 200, height: 100)
        let origin = PanelPositioner.marginOrigin(for: size, near: anchor, on: screen, gap: 8)

        let expectedY = anchor.midY - size.height / 2
        #expect(origin.y == expectedY)
    }

    @Test("clamps vertically to screen bounds")
    func verticalClamp() {
        let visibleFrame = screen.visibleFrame
        // Anchor near bottom edge
        let anchor = NSRect(x: 100, y: visibleFrame.minY, width: 400, height: 20)
        let size = NSSize(width: 200, height: 300)
        let origin = PanelPositioner.marginOrigin(for: size, near: anchor, on: screen, gap: 8)

        #expect(origin.y >= visibleFrame.minY)
        #expect(origin.y + size.height <= visibleFrame.maxY)
    }

    // MARK: - capHeight (D-12)

    @Test("capHeight passes size unchanged when height within cap")
    func capHeight_passesSizeUnchangedWhenWithinCap() {
        let visibleFrame = screen.visibleFrame
        let size = NSSize(width: 380, height: 260)
        let capped = PanelPositioner.capHeight(size, visibleFrame: visibleFrame, margin: 40)
        #expect(capped.height == 260)
        #expect(capped.width == 380)
    }

    @Test("capHeight clamps oversized height to visibleFrame.height - margin")
    func capHeight_clampsOversizedHeight() {
        let visibleFrame = screen.visibleFrame
        let oversized = NSSize(width: 380, height: visibleFrame.height + 200)
        let capped = PanelPositioner.capHeight(oversized, visibleFrame: visibleFrame, margin: 40)
        #expect(capped.height == visibleFrame.height - 40)
        #expect(capped.width == 380)
    }

    @Test("capHeight + marginOrigin keeps panel rect inside visibleFrame")
    func capHeight_composedWithMarginOrigin_staysInsideVisibleFrame() {
        let visibleFrame = screen.visibleFrame
        let anchor = NSRect(x: 100, y: visibleFrame.midY, width: 400, height: 20)
        let oversized = NSSize(width: 380, height: visibleFrame.height + 500)
        let capped = PanelPositioner.capHeight(oversized, visibleFrame: visibleFrame, margin: 40)
        let origin = PanelPositioner.marginOrigin(for: capped, near: anchor, on: screen, gap: 8)
        #expect(origin.y >= visibleFrame.minY)
        #expect(origin.y + capped.height <= visibleFrame.maxY)
    }
}
