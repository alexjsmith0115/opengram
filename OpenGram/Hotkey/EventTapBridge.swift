import CoreGraphics

/// File-scope C callback function for CGEventTap.
/// Must be a free function (not a closure or method) because CGEventTap requires @convention(c).
/// The actual implementation is in Plan 03 -- this file establishes the contract.
///
/// The callback receives the HotkeyManager instance via userInfo (Unmanaged bridge).
/// It should do minimal work: check key code + flags, then dispatch to main actor.
func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    return Unmanaged.passUnretained(event)
}
