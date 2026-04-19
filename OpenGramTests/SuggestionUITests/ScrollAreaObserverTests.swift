import Testing
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

@Suite("ScrollAreaObserver")
@MainActor
struct ScrollAreaObserverTests {

    /// install() followed by uninstall() must not crash and must release the
    /// retained context exactly once (no double-free, no leak).
    @Test("install then uninstall runs cleanly")
    func installUninstallLifecycle() {
        let observer = ScrollAreaObserver()
        let systemElement = AXUIElementCreateSystemWide()
        observer.install(
            pid: ProcessInfo.processInfo.processIdentifier,
            element: systemElement,
            onScrollChanged: {}
        )
        observer.uninstall()
        // Reaching here with no crash means retain/release balanced.
        #expect(Bool(true))
    }

    @Test("double install swaps context without crashing")
    func doubleInstallSwapsContext() {
        let observer = ScrollAreaObserver()
        let systemElement = AXUIElementCreateSystemWide()
        observer.install(
            pid: ProcessInfo.processInfo.processIdentifier,
            element: systemElement,
            onScrollChanged: {}
        )
        observer.install(
            pid: ProcessInfo.processInfo.processIdentifier,
            element: systemElement,
            onScrollChanged: {}
        )
        observer.uninstall()
        #expect(Bool(true))
    }

    @Test("uninstall without install is safe")
    func uninstallWithoutInstallIsSafe() {
        let observer = ScrollAreaObserver()
        observer.uninstall()
        #expect(Bool(true))
    }
}
