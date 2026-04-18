import Foundation
import CryptoKit

/// Cache key for paragraph-level LLM suggestions.
/// `bundleID` partitions entries so the same paragraph text across apps gets separate
/// entries (per-app eviction sweeps stay safe). `sha256` is the full 64-char hex digest
/// of the normalized paragraph text. CONTEXT.md §Data Model lines 104-113.
struct ParagraphHash: Hashable, Sendable {
    let bundleID: String
    let sha256: String

    init(bundleID: String, paragraphText: String) {
        self.bundleID = bundleID
        self.sha256 = Self.sha256Hex(of: paragraphText)
    }

    /// Escape hatch for tests and deserialization. Callers are responsible for supplying
    /// a pre-computed hex digest — no validation performed here.
    init(bundleID: String, sha256: String) {
        self.bundleID = bundleID
        self.sha256 = sha256
    }

    static func sha256Hex(of text: String) -> String {
        let normalized = normalize(text)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Matches `Sha256ParagraphHasher.normalize` byte-for-byte so both hashing
    /// surfaces agree on what "same paragraph" means.
    private static func normalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let trimmed = nfc.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }
}
