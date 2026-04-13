import Foundation

/// Caches binary AX capability results keyed by bundleID+version.
/// Persists to ~/Library/Application Support/OpenGram/ax-cache.json.
///
/// Uses NSLock for thread safety instead of actor to avoid forcing
/// callers into async context -- AXTextEngine calls isSupported/store
/// synchronously on the main thread during extraction.
final class AXCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
    private var entries: [String: Bool] = [:]
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

    func isSupported(bundleID: String, version: String?) -> Bool? {
        let key = Self.cacheKey(bundleID: bundleID, version: version)
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func store(bundleID: String, version: String?, supported: Bool) {
        let key = Self.cacheKey(bundleID: bundleID, version: version)
        lock.lock()
        entries[key] = supported
        lock.unlock()
        saveToDisk()
    }

    func saveToDisk() {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        do {
            let dir = cacheFileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            // D-07: silent failure -- no user-facing error for cache persistence
        }
    }

    func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoded = try JSONDecoder().decode([String: Bool].self, from: data)
            lock.lock()
            entries = decoded
            lock.unlock()
        } catch {
            // Corrupt or unreadable file: start with empty cache, no crash
            lock.lock()
            entries = [:]
            lock.unlock()
        }
    }

    private static func cacheKey(bundleID: String, version: String?) -> String {
        bundleID + ":" + (version ?? "unknown")
    }
}
