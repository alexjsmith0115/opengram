@preconcurrency import ApplicationServices
import Foundation
import os.log

/// Range-targeted AX text write with full-text fallback. Extracted from
/// `OverlayController.acceptSuggestion` (D-15). Shared by the per-suggestion
/// accept path and the rephrase-card accept path.
@MainActor
struct AXTextReplacer {
    let accessor: any AXAccessor

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "AXTextReplacer"
    )

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
        Self.logger.info("replace() start — range=(\(scalarRange.scalarStart), \(scalarRange.scalarLength)) replacement.len=\(replacement.count) isSettableErr=\(settableErr.rawValue) isSettable=\(isSettable) → rangeWrite=\(supportsRangeWrite)")

        if supportsRangeWrite {
            var cfRange = CFRange(location: scalarRange.scalarStart, length: scalarRange.scalarLength)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
                Self.logger.error("AXValueCreate(.cfRange) returned nil — falling back")
                return fallbackFullWrite(offset: scalarRange, replacement: replacement, element: element)
            }
            let selectError = accessor.setAttributeValue(
                element, kAXSelectedTextRangeAttribute, rangeValue
            )
            Self.logger.info("set kAXSelectedTextRangeAttribute → \(selectError.rawValue)")
            if selectError == .success {
                let replaceError = accessor.setAttributeValue(
                    element, kAXSelectedTextAttribute, replacement as CFString
                )
                Self.logger.info("set kAXSelectedTextAttribute → \(replaceError.rawValue)")
                if replaceError == .success { return true }
            }
            Self.logger.info("range path did not succeed — trying fallback")
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
        guard readError == .success, let currentText = readRef as? String else {
            Self.logger.error("fallback read failed — kAXValueAttribute err=\(readError.rawValue) textCast=\(readRef is String)")
            return false
        }

        let scalars = currentText.unicodeScalars
        guard offset.scalarStart >= 0, offset.scalarStart <= scalars.count else {
            Self.logger.error("fallback range out of bounds — start=\(offset.scalarStart) textScalars=\(scalars.count)")
            return false
        }
        let startIdx = scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)
        let end = offset.scalarStart + offset.scalarLength
        guard end <= scalars.count else {
            Self.logger.error("fallback end out of bounds — end=\(end) textScalars=\(scalars.count)")
            return false
        }
        let endIdx = scalars.index(startIdx, offsetBy: offset.scalarLength)
        guard let stringStart = startIdx.samePosition(in: currentText),
              let stringEnd = endIdx.samePosition(in: currentText) else {
            Self.logger.error("fallback scalar→String.Index conversion failed")
            return false
        }

        var newText = currentText
        newText.replaceSubrange(stringStart..<stringEnd, with: replacement)

        let writeError = accessor.setAttributeValue(
            element, kAXValueAttribute, newText as CFString
        )
        Self.logger.info("fallback set kAXValueAttribute → \(writeError.rawValue) (newText.len=\(newText.count))")
        return writeError == .success
    }
}
