import Testing
import AppKit

@testable import OpenGramLib

@Suite("OverlayWindow window properties")
@MainActor
struct OverlayWindowTests {

    @Test("canBecomeKey returns true")
    func canBecomeKeyIsTrue() {
        let window = OverlayWindow()
        #expect(window.canBecomeKey == true)
    }

    @Test("canBecomeMain returns false")
    func canBecomeMainIsFalse() {
        let window = OverlayWindow()
        #expect(window.canBecomeMain == false)
    }

    @Test("isOpaque returns false")
    func isOpaqueIsFalse() {
        let window = OverlayWindow()
        #expect(window.isOpaque == false)
    }

    @Test("backgroundColor is clear")
    func backgroundColorIsClear() {
        let window = OverlayWindow()
        #expect(window.backgroundColor == .clear)
    }

    @Test("level is floating")
    func levelIsFloating() {
        let window = OverlayWindow()
        #expect(window.level == .floating)
    }

    @Test("hasShadow is false")
    func hasShadowIsFalse() {
        let window = OverlayWindow()
        #expect(window.hasShadow == false)
    }

    @Test("ignoresMouseEvents is false (underlines need click events)")
    func ignoresMouseEventsIsFalse() {
        let window = OverlayWindow()
        #expect(window.ignoresMouseEvents == false)
    }
}
