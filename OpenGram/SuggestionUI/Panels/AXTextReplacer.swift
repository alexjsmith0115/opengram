@preconcurrency import ApplicationServices
import Foundation

/// Range-targeted AX text write with full-text fallback. Extracted from
/// `OverlayController.acceptSuggestion` (D-15). Shared by the Phase 3 per-suggestion
/// accept path and the Phase 18 rephrase-card accept path.
@MainActor
struct AXTextReplacer {
    let accessor: any AXAccessor

    /// Replaces `scalarRange` of `element`'s text with `replacement`.
    /// Primary path: set `kAXSelectedTextRangeAttribute` then `kAXSelectedTextAttribute` (D-11).
    /// Fallback path: read `kAXValueAttribute`, splice in-memory, write back.
    /// Returns true on success, false on any AX error.
    @discardableResult
    func replace(
        text replacement: String,
        in scalarRange: (scalarStart: Int, scalarLength: Int),
        of element: AXUIElement
    ) -> Bool {
        let (settableErr, isSettable) = accessor.isAttributeSettable(
            element, kAXSelectedTextRangeAttribute
        )
        let supportsRangeWrite = settableErr == .success && isSettable

        if supportsRangeWrite {
            var cfRange = CFRange(location: scalarRange.scalarStart, length: scalarRange.scalarLength)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
                return fallbackFullWrite(offset: scalarRange, replacement: replacement, element: element)
            }
            let selectError = accessor.setAttributeValue(
                element, kAXSelectedTextRangeAttribute, rangeValue
            )
            if selectError == .success {
                let replaceError = accessor.setAttributeValue(
                    element, kAXSelectedTextAttribute, replacement as CFString
                )
                if replaceError == .success { return true }
            }
        }
        return fallbackFullWrite(offset: scalarRange, replacement: replacement, element: element)
    }

    @discardableResult
    private func fallbackFullWrite(
        offset: (scalarStart: Int, scalarLength: Int),
        replacement: String,
        element: AXUIElement
    ) -> Bool {
        let (readError, readRef) = accessor.copyAttributeValue(element, kAXValueAttribute)
        guard readError == .success, let currentText = readRef as? String else { return false }

        let scalars = currentText.unicodeScalars
        guard offset.scalarStart >= 0, offset.scalarStart <= scalars.count else { return false }
        let startIdx = scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)
        let end = offset.scalarStart + offset.scalarLength
        guard end <= scalars.count else { return false }
        let endIdx = scalars.index(startIdx, offsetBy: offset.scalarLength)
        guard let stringStart = startIdx.samePosition(in: currentText),
              let stringEnd = endIdx.samePosition(in: currentText) else { return false }

        var newText = currentText
        newText.replaceSubrange(stringStart..<stringEnd, with: replacement)

        let writeError = accessor.setAttributeValue(
            element, kAXValueAttribute, newText as CFString
        )
        return writeError == .success
    }
}
