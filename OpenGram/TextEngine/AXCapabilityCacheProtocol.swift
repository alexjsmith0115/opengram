import Foundation

/// Protocol for AX capability cache, enabling DI for testing.
/// Production implementation: AXCapabilityCache (stores to disk).
/// Test implementation: StubCapabilityCache (in-memory only).
protocol AXCapabilityCacheProtocol: Sendable {
    func isSupported(bundleID: String, version: String?) -> Bool?
    func store(bundleID: String, version: String?, supported: Bool)

    /// Returns nil if notification reliability for this app has not been observed yet.
    /// Notification reliability is app-wide (no version key) — AX notification behavior
    /// does not change between app versions in practice.
    func isNotificationReliable(bundleID: String) -> Bool?
    func storeNotificationReliability(bundleID: String, reliable: Bool)

    // Phase 20 D-05: paragraph separator probe cache
    func separator(bundleID: String, version: String?) -> String?
    func storeSeparator(bundleID: String, version: String?, separator: String)
}
