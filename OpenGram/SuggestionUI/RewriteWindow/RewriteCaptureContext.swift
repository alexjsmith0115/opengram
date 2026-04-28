import Foundation
@preconcurrency import ApplicationServices

/// Snapshot of everything the rewrite session needs to know about the source
/// AX target, captured at hotkey time. Not mutated after construction.
@MainActor
struct RewriteCaptureContext {
    let capturedOriginal: String
    let writeBackStrategy: WriteBackStrategy
    let capabilities: AXCapabilities
    let axElement: AXUIElement
    let bundleID: String
    let elementBounds: CGRect?
}
