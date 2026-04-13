import Testing
import AppKit

@testable import OpenGramLib

@Suite("TargetAppObserver lifecycle")
struct TargetAppObserverTests {

    @Test("init creates object without crashing")
    func initDoesNotCrash() {
        let observer = TargetAppObserver()
        _ = observer
    }

    @Test("install with dummy PID does not crash")
    func installWithDummyPIDDoesNotCrash() {
        let observer = TargetAppObserver()
        // Use PID 1 (launchd) -- the observer won't fire notifications in tests
        // but should not crash on install
        observer.install(pid: 1, onDismiss: {})
        observer.uninstall()
    }

    @Test("uninstall is idempotent (calling twice does not crash)")
    func uninstallIsIdempotent() {
        let observer = TargetAppObserver()
        observer.install(pid: 1, onDismiss: {})
        observer.uninstall()
        observer.uninstall() // second call must not crash
    }

    @Test("install then uninstall clears observer state")
    func installUninstallClearsState() {
        let observer = TargetAppObserver()
        observer.install(pid: 1, onDismiss: {})
        observer.uninstall()
        // After uninstall a second install should work fine
        observer.install(pid: 1, onDismiss: {})
        observer.uninstall()
    }

    @Test("double install does not crash and implicitly uninstalls first")
    func doubleInstallDoesNotCrash() {
        let observer = TargetAppObserver()
        observer.install(pid: 1, onDismiss: {})
        observer.install(pid: 1, onDismiss: {}) // second install replaces first
        observer.uninstall()
    }
}
