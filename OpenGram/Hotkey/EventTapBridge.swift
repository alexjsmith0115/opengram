import CoreGraphics

/// File-scope C callback for CGEventTap.
/// Must be a free function -- CGEventTap requires @convention(c).
/// Does minimal work: extracts the HotkeyManager from userInfo and delegates.
func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    return manager.handle(proxy: proxy, type: type, event: event)
}
