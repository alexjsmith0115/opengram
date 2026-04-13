@preconcurrency import ApplicationServices

protocol AXTextEngineProtocol: AnyObject, Sendable {
    /// Extract text from the focused UI element in the frontmost app.
    /// Returns nil if AX is not available, no element is focused, or the element
    /// fails the capability probe (read + write required per D-08).
    @MainActor func extractText() -> TextContext?

    /// Write replacement text back to the AX element stored in the TextContext.
    /// Returns true if the write succeeded.
    /// Per D-12: caller must have explicit user acceptance before calling this.
    @MainActor func writeBack(context: TextContext, replacement: String) -> Bool

    /// Probe whether the focused element in a given app supports both AX read and write.
    /// Result is cached by AXCapabilityCache (D-09/D-10/D-11).
    @MainActor func probeCapability(element: AXUIElement) -> Bool
}
