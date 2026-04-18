import Foundation

/// Thrown by `withTimeout` when the wrapped operation exceeds the deadline.
struct TimeoutError: Error, Sendable {}

/// Races `operation` against a `Task.sleep(for: .seconds(seconds))` deadline.
/// The loser of the race is cancelled via `group.cancelAll()`.
///
/// Propagates `CancellationError` if the caller cancels the enclosing Task.
/// Propagates any other error the operation throws unchanged.
///
/// Swift 6 strict-concurrency: `operation` is `@Sendable @escaping` so it can cross
/// the task-group boundary; result `T` is `Sendable`.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let winner = try await group.next() else {
            throw TimeoutError()
        }
        return winner
    }
}
