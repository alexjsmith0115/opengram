/// Tracks whether an app's AX notifications are reliable by comparing notification events
/// against poll-detected text changes. Promotes to "reliable" after `threshold` consecutive
/// matched notification+poll ticks. Marks "unreliable" when poll detects a change that no
/// notification reported.
///
/// All access must be on @MainActor (same as TextMonitor).
@MainActor
struct ReliabilityDetector {

    private(set) var notificationFiredSinceLastPoll: Bool = false
    private(set) var consecutiveHits: Int = 0
    let threshold: Int

    init(threshold: Int = 5) {
        self.threshold = threshold
    }

    /// Call when an AX notification fires for the observed element.
    mutating func recordNotification() {
        notificationFiredSinceLastPoll = true
    }

    /// Call at each poll tick after comparing text. Returns the reliability verdict.
    /// - Parameter textChanged: whether poll detected a text change since last tick.
    /// - Returns: `.promoted` if threshold reached, `.markedUnreliable` if change without
    ///   notification, `.noChange` otherwise.
    mutating func evaluatePollTick(textChanged: Bool) -> Verdict {
        defer { notificationFiredSinceLastPoll = false }

        guard textChanged else { return .noChange }

        if !notificationFiredSinceLastPoll {
            consecutiveHits = 0
            return .markedUnreliable
        }

        consecutiveHits += 1
        if consecutiveHits >= threshold {
            return .promoted
        }
        return .noChange
    }

    /// Resets state for a new observed element.
    mutating func reset() {
        notificationFiredSinceLastPoll = false
        consecutiveHits = 0
    }

    enum Verdict {
        case noChange
        case markedUnreliable
        case promoted
    }
}
