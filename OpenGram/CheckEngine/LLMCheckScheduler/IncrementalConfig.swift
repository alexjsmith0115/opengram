import Foundation

/// DI-friendly reader for Phase 16's feature flag plus Phase 17 live-read tunables.
/// Scheduler holds this and re-reads per-call so a settings flip takes effect on the next check
/// without app relaunch. D-14.
///
/// Phase 17 extends this protocol with three live-read tunables per D-01/D-02/D-05:
/// `minIssueCount`, `minWordCount`, `idleDebounceSeconds`. Each is read per-access so UI
/// changes in the Advanced Settings tab propagate on the next qualifying check.
protocol IncrementalConfig: Sendable {
    var isIncrementalCheckingEnabled: Bool { get }
    var minIssueCount: Int { get }
    var minWordCount: Int { get }
    var idleDebounceSeconds: TimeInterval { get }
}

/// UserDefaults-backed default. Reads each key on every access (live-read, D-14).
/// Default when unset: `false` for the flag; 2 / 12 / 1.5 for the tunables (D-02, ROADMAP success criterion 4).
///
/// `@unchecked Sendable` because `UserDefaults` is thread-safe by design but not formally
/// declared Sendable in the Foundation SDK. Matches the pattern used elsewhere in the codebase
/// for DI-injected UserDefaults readers under Swift 6 strict concurrency.
struct UserDefaultsIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    static let defaultMinIssueCount: Int = 2
    static let defaultMinWordCount: Int = 12
    static let defaultIdleDebounceSeconds: TimeInterval = 1.5

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isIncrementalCheckingEnabled: Bool {
        defaults.bool(forKey: "llmIncrementalCheckingEnabled")
    }

    /// `defaults.object(forKey:)` (not `defaults.integer(forKey:)`) to distinguish unset from
    /// a user-set zero — `integer(forKey:)` returns 0 for missing keys, collapsing both cases.
    var minIssueCount: Int {
        defaults.object(forKey: "llmMinIssueCount") as? Int ?? Self.defaultMinIssueCount
    }

    var minWordCount: Int {
        defaults.object(forKey: "llmMinWordCount") as? Int ?? Self.defaultMinWordCount
    }

    var idleDebounceSeconds: TimeInterval {
        defaults.object(forKey: "llmIdleDebounceSeconds") as? Double ?? Self.defaultIdleDebounceSeconds
    }
}
