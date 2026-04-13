import Foundation

protocol HotkeyManagerProtocol: AnyObject, Sendable {
    func install()
    func uninstall()
    var onHotkeyFired: (@MainActor @Sendable () -> Void)? { get set }
}
