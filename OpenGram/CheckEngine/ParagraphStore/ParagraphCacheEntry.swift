import Foundation

/// Value-type cache entry held by `ParagraphSuggestionStore`. `state` mutates in place
/// as the paragraph progresses through `pending → ready/readyEmpty/failed` or is
/// dismissed / accepted by the user. CONTEXT.md lines 134-141.
struct ParagraphCacheEntry: @unchecked Sendable {
    let hash: ParagraphHash
    let originalText: String
    var state: ParagraphSuggestionState
}
