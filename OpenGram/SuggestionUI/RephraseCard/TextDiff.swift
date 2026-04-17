import Foundation

enum DiffSegment: Equatable, Sendable {
    case unchanged(String)
    case added(String)
    case removed(String)
}

enum TextDiff {
    /// Word-level LCS diff between `original` and `revised`.
    /// Whitespace-tokenized via `Character.isWhitespace` (handles Unicode whitespace).
    /// Adjacent same-kind segments are coalesced into a single segment joined by single spaces.
    static func segments(original: String, revised: String) -> [DiffSegment] {
        let a = tokenize(original)
        let b = tokenize(revised)
        if a.isEmpty && b.isEmpty { return [] }
        if a.isEmpty { return [.added(b.joined(separator: " "))] }
        if b.isEmpty { return [.removed(a.joined(separator: " "))] }

        // DP matrix
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] { dp[i][j] = dp[i - 1][j - 1] + 1 }
                else { dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]) }
            }
        }

        // Traceback emitting raw segments per-token (reverse)
        var reversed: [DiffSegment] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                reversed.append(.unchanged(a[i - 1])); i -= 1; j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                reversed.append(.removed(a[i - 1])); i -= 1
            } else {
                reversed.append(.added(b[j - 1])); j -= 1
            }
        }
        while i > 0 { reversed.append(.removed(a[i - 1])); i -= 1 }
        while j > 0 { reversed.append(.added(b[j - 1])); j -= 1 }

        let ordered = Array(reversed.reversed())
        return coalesce(ordered)
    }

    static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func coalesce(_ segs: [DiffSegment]) -> [DiffSegment] {
        var out: [DiffSegment] = []
        for seg in segs {
            if let last = out.last, sameKind(last, seg) {
                out.removeLast()
                out.append(merge(last, seg))
            } else {
                out.append(seg)
            }
        }
        return out
    }

    private static func sameKind(_ a: DiffSegment, _ b: DiffSegment) -> Bool {
        switch (a, b) {
        case (.unchanged, .unchanged), (.added, .added), (.removed, .removed): return true
        default: return false
        }
    }

    private static func merge(_ a: DiffSegment, _ b: DiffSegment) -> DiffSegment {
        switch (a, b) {
        case (.unchanged(let x), .unchanged(let y)): return .unchanged("\(x) \(y)")
        case (.added(let x), .added(let y)):         return .added("\(x) \(y)")
        case (.removed(let x), .removed(let y)):     return .removed("\(x) \(y)")
        default: return b
        }
    }
}
