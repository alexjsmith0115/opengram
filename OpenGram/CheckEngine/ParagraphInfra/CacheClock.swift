import Foundation

/// Injectable wall-clock abstraction. `SystemClock` returns `Date()`; tests inject
/// a fake clock for deterministic TTL assertions. D-14.
protocol CacheClock: Sendable {
    func now() -> Date
}

struct SystemClock: CacheClock {
    func now() -> Date { Date() }
}
