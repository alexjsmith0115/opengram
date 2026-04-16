import Foundation

/// Caches binary AX capability results keyed by bundleID+version,
/// and AX notification reliability keyed by bundleID (app-wide).
/// Persists to ~/Library/Application Support/OpenGram/ax-cache.json.
///
/// Uses NSLock for thread safety instead of actor to avoid forcing
/// callers into async context -- AXTextEngine calls isSupported/store
/// synchronously on the main thread during extraction.
final class AXCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {

    // MARK: - Disk format

    /// Wrapper struct for the JSON file, supporting both dictionaries in one file.
    /// Backward compatibility: if the old flat [String: Bool] format is detected
    /// on disk, it is treated as `capabilities` with empty `notifications`.
    private struct CacheData: Codable {
        var capabilities: [String: Bool]
        var notifications: [String: Bool]
    }

    // MARK: - State

    private var entries: [String: Bool] = [:]
    private var notificationEntries: [String: Bool] = [:]
    private let lock = NSLock()
    private let cacheFileURL: URL

    static var defaultCacheFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenGram")
            .appendingPathComponent("ax-cache.json")
    }

    init(cacheFileURL: URL? = nil) {
        self.cacheFileURL = cacheFileURL ?? Self.defaultCacheFileURL
        loadFromDisk()
    }

    // MARK: - AX Capability

    func isSupported(bundleID: String, version: String?) -> Bool? {
        let key = Self.capabilityKey(bundleID: bundleID, version: version)
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func store(bundleID: String, version: String?, supported: Bool) {
        let key = Self.capabilityKey(bundleID: bundleID, version: version)
        lock.lock()
        entries[key] = supported
        lock.unlock()
        saveToDisk()  // saveToDisk() snapshots under its own lock
    }

    // MARK: - Notification Reliability

    func isNotificationReliable(bundleID: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return notificationEntries[bundleID]
    }

    func storeNotificationReliability(bundleID: String, reliable: Bool) {
        lock.lock()
        notificationEntries[bundleID] = reliable
        lock.unlock()
        saveToDisk()  // saveToDisk() snapshots under its own lock
    }

    // MARK: - Persistence

    func saveToDisk() {
        lock.lock()
        let data = CacheData(capabilities: entries, notifications: notificationEntries)
        lock.unlock()

        do {
            let dir = cacheFileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: cacheFileURL, options: .atomic)
        } catch {
            // D-07: non-critical — cache is reconstructable via probing
        }
    }

    func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }

        do {
            let raw = try Data(contentsOf: cacheFileURL)
            if let wrapper = try? JSONDecoder().decode(CacheData.self, from: raw) {
                lock.lock()
                entries = wrapper.capabilities
                notificationEntries = wrapper.notifications
                lock.unlock()
            } else if let legacy = try? JSONDecoder().decode([String: Bool].self, from: raw) {
                // Backward compat: old format was a plain [String: Bool] for capabilities only
                lock.lock()
                entries = legacy
                notificationEntries = [:]
                lock.unlock()
            } else {
                lock.lock()
                entries = [:]
                notificationEntries = [:]
                lock.unlock()
            }
        } catch {
            lock.lock()
            entries = [:]
            notificationEntries = [:]
            lock.unlock()
        }
    }

    // MARK: - Key helpers

    private static func capabilityKey(bundleID: String, version: String?) -> String {
        bundleID + ":" + (version ?? "unknown")
    }
}
