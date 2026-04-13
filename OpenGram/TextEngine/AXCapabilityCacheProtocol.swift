import Foundation

/// Protocol for AX capability cache, enabling DI for testing.
/// Production implementation: AXCapabilityCache (stores to disk).
/// Test implementation: StubCapabilityCache (in-memory only).
protocol AXCapabilityCacheProtocol: Sendable {
    func isSupported(bundleID: String, version: String?) -> Bool?
    func store(bundleID: String, version: String?, supported: Bool)
}
