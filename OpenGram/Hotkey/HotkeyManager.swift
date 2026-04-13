import CoreGraphics
import AppKit
import Foundation

final class HotkeyManager: HotkeyManagerProtocol, @unchecked Sendable {
    private(set) var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotkeyFired: (@MainActor @Sendable () -> Void)?

    func install() {
    }

    func uninstall() {
    }

    nonisolated func isHotkey(_ event: CGEvent) -> Bool {
        return false
    }

    nonisolated func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        return Unmanaged.passUnretained(event)
    }
}
