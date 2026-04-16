import Foundation

struct ParagraphCacheKey: Hashable, Sendable {
    let bundleID: String
    let paragraphHash: UInt64
}

struct CacheEntry: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case pending
        case active
        case dismissed
    }
    var status: Status
    var suggestions: [LLMStyleSuggestion]
    var lastAccessedAt: Date
}

/// Per-bundleID LRU+TTL cache of LLM suggestion results. Keyed on
/// `(bundleID, paragraphHash)`. INCR-06, INCR-07, INCR-10. Substring-offset
/// contract (INCR-12) is preserved by storing `LLMStyleSuggestion` values
/// verbatim — no index serialization. D-09 through D-17.
actor ParagraphSuggestionCache {

    static let defaultTTL: TimeInterval = 30 * 60
    static let defaultMaxEntriesPerBundle: Int = 500

    private let clock: CacheClock
    private let ttl: TimeInterval
    private let maxEntriesPerBundle: Int
    private var partitions: [String: [UInt64: CacheEntry]] = [:]

    init(clock: CacheClock = SystemClock(),
         ttl: TimeInterval = ParagraphSuggestionCache.defaultTTL,
         maxEntriesPerBundle: Int = ParagraphSuggestionCache.defaultMaxEntriesPerBundle) {
        self.clock = clock
        self.ttl = ttl
        self.maxEntriesPerBundle = maxEntriesPerBundle
    }

    func lookup(_ key: ParagraphCacheKey) -> CacheEntry? {
        guard var bundle = partitions[key.bundleID],
              var entry = bundle[key.paragraphHash] else {
            return nil
        }
        entry.lastAccessedAt = clock.now()
        bundle[key.paragraphHash] = entry
        partitions[key.bundleID] = bundle
        return entry
    }

    func upsert(_ key: ParagraphCacheKey,
                status: CacheEntry.Status,
                suggestions: [LLMStyleSuggestion]) {
        var bundle = partitions[key.bundleID] ?? [:]
        bundle[key.paragraphHash] = CacheEntry(
            status: status,
            suggestions: suggestions,
            lastAccessedAt: clock.now()
        )
        partitions[key.bundleID] = bundle
        evictIfNeeded()
    }

    func markDismissed(_ key: ParagraphCacheKey) {
        guard var bundle = partitions[key.bundleID],
              var entry = bundle[key.paragraphHash] else {
            return
        }
        entry.status = .dismissed
        entry.lastAccessedAt = clock.now()
        bundle[key.paragraphHash] = entry
        partitions[key.bundleID] = bundle
    }

    func evictIfNeeded() {
        let now = clock.now()
        for (bundleID, var bundle) in partitions {
            // Step 1: TTL sweep (D-15, D-16).
            for (hash, entry) in bundle where now.timeIntervalSince(entry.lastAccessedAt) > ttl {
                bundle.removeValue(forKey: hash)
            }
            // Step 2: LRU cap — partition-scoped (D-13, D-15).
            if bundle.count > maxEntriesPerBundle {
                let sorted = bundle.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
                let toDrop = bundle.count - maxEntriesPerBundle
                for (hash, _) in sorted.prefix(toDrop) {
                    bundle.removeValue(forKey: hash)
                }
            }
            if bundle.isEmpty {
                partitions.removeValue(forKey: bundleID)
            } else {
                partitions[bundleID] = bundle
            }
        }
    }
}
