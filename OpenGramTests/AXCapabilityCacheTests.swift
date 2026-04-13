import Testing
import Foundation

@testable import OpenGramLib

@Suite("AXCapabilityCache in-memory operations")
struct AXCapabilityCacheMemoryTests {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("opengram-test-\(UUID().uuidString)")
            .appendingPathComponent("ax-cache.json")
    }

    @Test("isSupported returns nil for unknown bundleID+version (not yet probed)")
    func unknownReturnsNil() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        let result = cache.isSupported(bundleID: "com.unknown.app", version: "1.0")
        #expect(result == nil)
    }

    @Test("store then isSupported returns true when stored as supported")
    func storeTrueReturnsTrue() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        cache.store(bundleID: "com.apple.Notes", version: "14.5", supported: true)
        let result = cache.isSupported(bundleID: "com.apple.Notes", version: "14.5")
        #expect(result == true)
    }

    @Test("store then isSupported returns false when stored as unsupported")
    func storeFalseReturnsFalse() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        cache.store(bundleID: "com.google.Chrome", version: "120.0", supported: false)
        let result = cache.isSupported(bundleID: "com.google.Chrome", version: "120.0")
        #expect(result == false)
    }

    @Test("isSupported returns nil when version changes (D-10 invalidation)")
    func versionChangeReturnsNil() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        cache.store(bundleID: "com.apple.Notes", version: "14.5", supported: true)

        let result = cache.isSupported(bundleID: "com.apple.Notes", version: "14.6")
        #expect(result == nil)
    }

    @Test("Same bundleID with different version returns nil (version-keyed)")
    func differentVersionReturnsNil() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        cache.store(bundleID: "com.apple.Notes", version: "14.5", supported: true)
        cache.store(bundleID: "com.apple.Notes", version: "14.6", supported: false)

        #expect(cache.isSupported(bundleID: "com.apple.Notes", version: "14.5") == true)
        #expect(cache.isSupported(bundleID: "com.apple.Notes", version: "14.6") == false)
        #expect(cache.isSupported(bundleID: "com.apple.Notes", version: "15.0") == nil)
    }

    @Test("Nil version uses 'unknown' as cache key component")
    func nilVersionUsesUnknown() {
        let cache = AXCapabilityCache(cacheFileURL: makeTempFileURL())
        cache.store(bundleID: "com.test.app", version: nil, supported: true)
        #expect(cache.isSupported(bundleID: "com.test.app", version: nil) == true)
    }
}

@Suite("AXCapabilityCache disk persistence")
struct AXCapabilityCacheDiskTests {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("opengram-test-\(UUID().uuidString)")
            .appendingPathComponent("ax-cache.json")
    }

    @Test("saveToDisk writes JSON file to specified path")
    func saveToDiskWritesFile() throws {
        let fileURL = makeTempFileURL()
        let cache = AXCapabilityCache(cacheFileURL: fileURL)
        cache.store(bundleID: "com.apple.Notes", version: "14.5", supported: true)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        #expect(data.count > 0)

        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @Test("loadFromDisk restores entries from JSON file")
    func loadFromDiskRestoresEntries() throws {
        let fileURL = makeTempFileURL()
        let original = AXCapabilityCache(cacheFileURL: fileURL)
        original.store(bundleID: "com.apple.Notes", version: "14.5", supported: true)
        original.store(bundleID: "com.google.Chrome", version: "120.0", supported: false)

        let restored = AXCapabilityCache(cacheFileURL: fileURL)
        #expect(restored.isSupported(bundleID: "com.apple.Notes", version: "14.5") == true)
        #expect(restored.isSupported(bundleID: "com.google.Chrome", version: "120.0") == false)

        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    @Test("loadFromDisk with missing file returns empty cache (no crash)")
    func loadFromDiskMissingFile() {
        let fileURL = makeTempFileURL()
        let cache = AXCapabilityCache(cacheFileURL: fileURL)

        #expect(cache.isSupported(bundleID: "com.any.app", version: "1.0") == nil)
    }

    @Test("loadFromDisk with corrupt JSON returns empty cache (no crash)")
    func loadFromDiskCorruptJSON() throws {
        let fileURL = makeTempFileURL()
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not valid json {{{".data(using: .utf8)!.write(to: fileURL)

        let cache = AXCapabilityCache(cacheFileURL: fileURL)
        #expect(cache.isSupported(bundleID: "com.any.app", version: "1.0") == nil)

        try? FileManager.default.removeItem(at: dir)
    }
}
