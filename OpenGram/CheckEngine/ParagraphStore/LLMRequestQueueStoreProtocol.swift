import Foundation

/// Callback protocol the queue invokes after a request completes, fails, or times out.
/// Exists to break the queue ↔ store circular dependency at init time.
/// The concrete implementor is `ParagraphSuggestionStore`.
///
/// Contract: `handleQueueResponse` is NEVER called for cancelled requests.
/// `queue.cancel(hash:)` suppresses the callback — CONTEXT.md 391.
protocol LLMRequestQueueStore: AnyObject, Sendable {
    func handleQueueResponse(
        hash: ParagraphHash,
        bundleID: String,
        result: Result<[LLMStyleSuggestion], Error>
    ) async
}
