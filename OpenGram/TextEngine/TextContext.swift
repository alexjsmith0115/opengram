@preconcurrency import ApplicationServices
import Foundation

/// How text was extracted from the target app.
/// Per D-05: only AX methods are used. No clipboard extraction.
enum ExtractionMethod: String, Codable, Sendable {
    case axDirectSelection = "ax-direct-selection"
    case axDirectFull = "ax-direct-full"
}

/// Captures all context from a text extraction operation.
/// Per TEXT-05: text, source app bundle ID, extraction method, selection range, element bounds.
/// Also retains the AXUIElement reference for write-back (D-12).
struct TextContext: Sendable {
    let text: String
    let bundleID: String
    let extractionMethod: ExtractionMethod
    let selectionRange: CFRange?
    let elementBounds: CGRect?

    // AXUIElement is a CoreFoundation IPC proxy -- thread-safe but not marked Sendable
    nonisolated(unsafe) let axElement: AXUIElement
}
