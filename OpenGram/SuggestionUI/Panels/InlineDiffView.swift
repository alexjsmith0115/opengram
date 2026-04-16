import SwiftUI

/// Word-level diff renderer for LLM suggestion pairs.
/// Removed words get strikethrough + red tint; added words get bold + blue tint; unchanged words are unstyled.
struct InlineDiffView: View {
    let original: String
    let revised: String

    var body: some View {
        diffText
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var diffText: Text {
        let ops = wordDiff(from: original.words, to: revised.words)
        return ops.reduce(Text("")) { result, op in
            result + op.rendered
        }
    }
}

// MARK: - Diff Operation

private enum DiffOp {
    case unchanged(String)
    case removed(String)
    case added(String)

    var rendered: Text {
        switch self {
        case .unchanged(let w):
            return Text(w + " ")
        case .removed(let w):
            return Text(w + " ")
                .strikethrough(true, color: .red)
                .foregroundColor(.secondary)
        case .added(let w):
            return Text(w + " ")
                .bold()
                .foregroundColor(.blue)
        }
    }
}

// MARK: - LCS-based word diff

/// Returns a minimal edit sequence using longest common subsequence.
private func wordDiff(from source: [String], to target: [String]) -> [DiffOp] {
    let m = source.count
    let n = target.count

    // Build LCS table
    var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 1...max(m, 1) where i <= m {
        for j in 1...max(n, 1) where j <= n {
            if source[i - 1] == target[j - 1] {
                lcs[i][j] = lcs[i - 1][j - 1] + 1
            } else {
                lcs[i][j] = max(lcs[i - 1][j], lcs[i][j - 1])
            }
        }
    }

    // Backtrack to produce ops
    var ops: [DiffOp] = []
    var i = m, j = n
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && source[i - 1] == target[j - 1] {
            ops.append(.unchanged(source[i - 1]))
            i -= 1; j -= 1
        } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
            ops.append(.added(target[j - 1]))
            j -= 1
        } else {
            ops.append(.removed(source[i - 1]))
            i -= 1
        }
    }
    return ops.reversed()
}

// MARK: - Helpers

private extension String {
    var words: [String] {
        components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
}
