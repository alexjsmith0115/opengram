import Foundation

/// State machine for a cached paragraph's LLM suggestion lifecycle.
/// CONTEXT.md lines 120-132. `.readyEmpty` is distinct from `.ready(Suggestion)` so
/// the cache remembers "we already asked, nothing to suggest" and does NOT re-fire
/// requests on subsequent reconcile ticks (PLL-14).
///
/// Note: Swift's synthesized `Sendable` does not cover `Error` associated values.
/// Using `@unchecked Sendable` is safe because the enum itself is a value type and
/// `Error` values captured here are always constructed by `LLMRequestQueue` on a
/// single actor and handed to the store — never mutated after insertion.
enum ParagraphSuggestionState: @unchecked Sendable {
    case pending(submittedAt: Date)
    case ready(Suggestion)
    case readyEmpty
    case failed(Error)
    case dismissed
    case accepted
}

extension ParagraphSuggestionState {
    /// Projection for tests — side-steps the `Error` associated value equality problem.
    /// Production code switches exhaustively on the enum and never needs equality.
    enum Kind: Sendable, Equatable {
        case pending
        case ready
        case readyEmpty
        case failed
        case dismissed
        case accepted
    }

    var kind: Kind {
        switch self {
        case .pending:     return .pending
        case .ready:       return .ready
        case .readyEmpty:  return .readyEmpty
        case .failed:      return .failed
        case .dismissed:   return .dismissed
        case .accepted:    return .accepted
        }
    }
}
