import Foundation

/// Snapshot output of `ParagraphSplitter.split`. Used by `ParagraphSuggestionStore.reconcile`
/// to decide cache misses, caret-skip targets, and eviction sweeps. CONTEXT.md lines 146-152.
struct ParagraphSet: Sendable {
    struct Entry: Sendable {
        let hash: ParagraphHash
        let text: String
    }

    let bundleID: String
    let paragraphs: [Entry]
    let caretParagraphHash: ParagraphHash?

    init(bundleID: String, paragraphs: [Entry], caretParagraphHash: ParagraphHash?) {
        self.bundleID = bundleID
        self.paragraphs = paragraphs
        self.caretParagraphHash = caretParagraphHash
    }
}
