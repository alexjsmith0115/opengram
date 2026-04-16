import Foundation

/// DI-friendly reader for Phase 16's feature flag (and future Phase 17 tunables).
/// Scheduler holds this and re-reads per-call so a settings flip takes effect on the next check
/// without app relaunch. D-14.
protocol IncrementalConfig: Sendable {
    var isIncrementalCheckingEnabled: Bool { get }
}

/// UserDefaults-backed default. Reads the `llmIncrementalCheckingEnabled` key on each access.
/// Default when unset: false (flag-off path per §10 rollout).
///
/// `@unchecked Sendable` because `UserDefaults` is thread-safe by design but not formally
/// declared Sendable in the Foundation SDK. Matches the pattern used elsewhere in the codebase
/// for DI-injected UserDefaults readers under Swift 6 strict concurrency.
struct UserDefaultsIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var isIncrementalCheckingEnabled: Bool {
        defaults.bool(forKey: "llmIncrementalCheckingEnabled")
    }
}
