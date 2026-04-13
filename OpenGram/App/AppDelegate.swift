import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wired in Plan 05
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup in Plan 05
    }
}
