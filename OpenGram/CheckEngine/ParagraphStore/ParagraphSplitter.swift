import Foundation

/// Paragraph splitter: caret-aware, separator-probe-cached, emits `ParagraphSet` keyed on
/// `ParagraphHash`. Distinct from `DoubleNewlineSplitter` (different output
/// type + separator strategy + caret identification). DoubleNewlineSplitter is slated
/// for deletion when migration completes.
///
/// Separator strategy (D-05 / CONTEXT.md §Separator strategy):
/// 1. Probe `AXCapabilityCache` for cached separator keyed on `bundleID + version`.
///    Probed values: `"\n\n"`, `"\n"`, `""` (whole text = one paragraph).
/// 2. On cache miss: inspect `text`. If contains `\n{2,}` → `"\n\n"`; else if contains
///    `\n` → `"\n"`; else → `""`. Persist probe unless text is empty (self-corrects on
///    next tick per CONTEXT.md 316-317).
struct ParagraphSplitter: Sendable {
    let capabilityCache: any AXCapabilityCacheProtocol

    init(capabilityCache: any AXCapabilityCacheProtocol) {
        self.capabilityCache = capabilityCache
    }

    func split(
        text: String,
        bundleID: String,
        version: String?,
        caretOffset: Int?
    ) -> ParagraphSet {
        guard !text.isEmpty else {
            return ParagraphSet(bundleID: bundleID, paragraphs: [], caretParagraphHash: nil)
        }

        let separator = resolveSeparator(text: text, bundleID: bundleID, version: version)

        // Walk text in scalar space so caretOffset (scalar offset) compares correctly.
        let scalars = Array(text.unicodeScalars)
        var paragraphs: [ParagraphSet.Entry] = []
        var caretParagraphHash: ParagraphHash? = nil
        var segmentStart = 0
        var i = 0

        while i < scalars.count {
            let runEnd = scanSeparatorRun(from: i, in: scalars, separator: separator)
            if runEnd > i {
                emit(
                    from: segmentStart, upTo: i, scalars: scalars,
                    bundleID: bundleID, caretOffset: caretOffset,
                    paragraphs: &paragraphs, caretParagraphHash: &caretParagraphHash
                )
                segmentStart = runEnd
                i = runEnd
                continue
            }
            i += 1
        }
        if segmentStart < scalars.count {
            emit(
                from: segmentStart, upTo: scalars.count, scalars: scalars,
                bundleID: bundleID, caretOffset: caretOffset,
                paragraphs: &paragraphs, caretParagraphHash: &caretParagraphHash
            )
        }

        return ParagraphSet(
            bundleID: bundleID,
            paragraphs: paragraphs,
            caretParagraphHash: caretParagraphHash
        )
    }

    // MARK: - Separator resolution

    private func resolveSeparator(text: String, bundleID: String, version: String?) -> String {
        if let cached = capabilityCache.separator(bundleID: bundleID, version: version), !cached.isEmpty {
            return cached
        }
        let probed = probeSeparator(text: text)
        if !probed.isEmpty {
            capabilityCache.storeSeparator(bundleID: bundleID, version: version, separator: probed)
        }
        return probed
    }

    private func probeSeparator(text: String) -> String {
        if text.range(of: "\n{2,}", options: .regularExpression) != nil { return "\n\n" }
        if text.contains("\n") { return "\n" }
        return ""
    }

    // MARK: - Scanning

    /// Returns the scalar index AFTER the separator run starting at `start`, or `start`
    /// if no separator match.
    private func scanSeparatorRun(
        from start: Int,
        in scalars: [Unicode.Scalar],
        separator: String
    ) -> Int {
        guard !separator.isEmpty else { return start }
        let scalar = scalars[start]
        guard scalar == "\n" else { return start }

        if separator == "\n\n" {
            // Consume run of \n; only count as separator if run length >= 2.
            var end = start
            while end < scalars.count, scalars[end] == "\n" { end += 1 }
            return (end - start >= 2) ? end : start
        } else {
            // separator == "\n"
            return start + 1
        }
    }

    private func emit(
        from start: Int,
        upTo end: Int,
        scalars: [Unicode.Scalar],
        bundleID: String,
        caretOffset: Int?,
        paragraphs: inout [ParagraphSet.Entry],
        caretParagraphHash: inout ParagraphHash?
    ) {
        guard start < end else { return }
        let raw = String(String.UnicodeScalarView(scalars[start..<end]))
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hash = ParagraphHash(bundleID: bundleID, paragraphText: trimmed)
        paragraphs.append(ParagraphSet.Entry(hash: hash, text: trimmed))
        if let caret = caretOffset, caret >= start, caret < end {
            caretParagraphHash = hash
        }
    }
}
