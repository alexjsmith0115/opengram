import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: (any HotkeyManagerProtocol)?
    private var textEngine: (any AXTextEngineProtocol)?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Wired in Plan 05
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Cleanup in Plan 05
    }
}
