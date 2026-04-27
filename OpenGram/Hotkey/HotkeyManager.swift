import CoreGraphics
import AppKit
import Foundation
import os.log

// @unchecked Sendable: The C callback bridge inherently crosses isolation boundaries.
// Properties are accessed from the callback thread + main thread in a controlled manner.
final class HotkeyManager: HotkeyManagerProtocol, @unchecked Sendable {

    enum HealthCheckAction: Equatable {
        case doNothing
        case reenable
        case retryInstall
    }

    static func healthCheckAction(tapExists: Bool, isEnabled: Bool) -> HealthCheckAction {
        if !tapExists { return .retryInstall }
        if !isEnabled { return .reenable }
        return .doNothing
    }

    private static let kVK_ANSI_G: CGKeyCode = 0x05
    private static let logger = Log.logger(for: "HotkeyManager")

    private(set) var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var healthTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    var onHotkeyFired: (@MainActor @Sendable (HotkeyAction) -> Void)?

    deinit {
        uninstall()
    }

    func install() {
        if eventTap != nil {
            uninstall()
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Self.logger.info("AXIsProcessTrusted: \(trusted)")

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            Self.logger.warning("Failed to create event tap — grant Accessibility permission and it will retry automatically")
            startHealthCheckTimer()
            return
        }
        Self.logger.info("Event tap created successfully")

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        startHealthCheckTimer()
    }

    func uninstall() {
        healthTimer?.invalidate()
        healthTimer = nil

        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    nonisolated func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableTapIfNeeded()
            return nil
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if isHotkey(event) {
            Task { @MainActor in self.onHotkeyFired?(.check) }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    nonisolated func isHotkey(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.kVK_ANSI_G else {
            return false
        }
        let flags = event.flags
        let required: CGEventFlags = [.maskControl, .maskShift]
        let relevant = flags.intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand])
        return relevant == required
    }

    // MARK: - Health Check

    func startHealthCheckTimer() {
        guard healthTimer == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reenableTapIfNeeded()
        }

        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.reenableTapIfNeeded()
        }
    }

    func reenableTapIfNeeded() {
        let tapExists = eventTap != nil
        let isEnabled = eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        let action = Self.healthCheckAction(tapExists: tapExists, isEnabled: isEnabled)

        switch action {
        case .doNothing:
            return
        case .retryInstall:
            guard AXIsProcessTrusted() else { return }
            Self.logger.info("Permission granted — retrying event tap install")
            reinstall()
        case .reenable:
            guard let tap = eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                reinstall()
            }
        }
    }

    func reinstall() {
        uninstall()
        install()
    }
}
