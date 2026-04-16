import Foundation
import CryptoKit

/// Produces stable 64-bit hashes for paragraph-level cache keys. Normalizes whitespace
/// and Unicode form so the same visible text across apps hashes identically; preserves
/// case and punctuation so meaningful edits invalidate cache entries. D-05, D-06, D-07, D-08.
protocol ParagraphHashing: Sendable {
    func hash(_ text: String) -> UInt64
}

struct Sha256ParagraphHasher: ParagraphHashing {

    func hash(_ text: String) -> UInt64 {
        let normalized = normalize(text)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        var result: UInt64 = 0
        for byte in digest.prefix(8) {
            result = (result << 8) | UInt64(byte)
        }
        return result
    }

    private func normalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let trimmed = nfc.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }
}
