import Foundation

protocol HotkeyManagerProtocol: AnyObject, Sendable {
    /// Install the CGEventTap and start listening for the global hotkey.
    func install()

    /// Remove the CGEventTap and stop listening.
    func uninstall()

    /// Callback fired on the main actor when the hotkey (Ctrl+Shift+G) is detected.
    var onHotkeyFired: (@MainActor @Sendable () -> Void)? { get set }
}
