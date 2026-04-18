import Foundation

/// NSLock-backed thread-safe holder of the per-bundle live text. The
/// `ParagraphSuggestionStore` actor reads from it via its `textProvider` closure
/// without a MainActor hop; `TextMonitor.driveStoreOnValueChange` +
/// `driveStoreOnFocusChange` write into it via the `textBoxWriter` hook on every
/// AX value/focus change.
///
/// Why NSLock and not MainActor: the store actor calls `textProvider(bundleID)`
/// synchronously from inside response handling. Hopping to MainActor from an actor
/// context requires `await`, which would change the callback signature and force
/// every store method to be reentrant. NSLock is cheaper and matches the actor-safe
/// access pattern already used by other low-level caches in the codebase.
final class MainActorTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var textByBundle: [String: String] = [:]

    func read(bundleID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return textByBundle[bundleID]
    }

    func write(bundleID: String, text: String) {
        lock.lock(); defer { lock.unlock() }
        textByBundle[bundleID] = text
    }
}
