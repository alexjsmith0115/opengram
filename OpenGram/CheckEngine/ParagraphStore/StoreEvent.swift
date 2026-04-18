import Foundation

/// Event emitted by `ParagraphSuggestionStore` over its `AsyncStream<StoreEvent>`
/// whenever cache state or displayed-set membership changes for a bundleID.
/// Coarse-grained by design — consumers re-read `renderableSuggestions(for:)` on every tick.
/// CONTEXT.md lines 158-162.
enum StoreEvent: Sendable {
    case suggestionsChanged(bundleID: String)
}
