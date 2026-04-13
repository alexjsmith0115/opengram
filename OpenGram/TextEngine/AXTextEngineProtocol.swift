@preconcurrency import ApplicationServices

protocol AXTextEngineProtocol: AnyObject, Sendable {
    @MainActor func extractText() -> TextContext?
    @MainActor func writeBack(context: TextContext, replacement: String) -> Bool
    @MainActor func probeCapability(element: AXUIElement) -> Bool
}
