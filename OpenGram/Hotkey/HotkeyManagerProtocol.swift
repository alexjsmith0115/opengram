import Foundation

protocol HotkeyManagerProtocol: AnyObject, Sendable {
    /// Install the CGEventTap and start listening for the global hotkey.
    func install()

    /// Remove the CGEventTap and stop listening.
    func uninstall()

    /// Callback fired on the main actor when a configured hotkey is detected,
    /// tagged with a `HotkeyAction` discriminator for dispatch.
    var onHotkeyFired: (@MainActor @Sendable (HotkeyAction) -> Void)? { get set }
}
