import Testing
import Foundation
@testable import OpenGramLib

/// Test-local fake. Re-declared to keep the cache suite decoupled from `CacheClockTests`
/// (where the same shape lives) — D-19.
private final class FakeClock: CacheClock, @unchecked Sendable {
    var current: Date
    init(_ seed: Date) { self.current = seed }
    func now() -> Date { current }
}

private func makeSuggestion(_ label: String = "x") -> LLMStyleSuggestion {
    LLMStyleSuggestion(
        category: .clarity,
        originalText: "orig \(label)",
        revisedText: "rev \(label)",
        explanation: "why \(label)",
        confidence: 8
    )
}

private func makeKey(bundle: String = "com.test", hash: UInt64) -> ParagraphCacheKey {
    ParagraphCacheKey(bundleID: bundle, paragraphHash: hash)
}

@Suite struct ParagraphSuggestionCacheTests {

    // MARK: - Keying (INCR-06)

    @Test func lookupMissReturnsNil() async {
        let cache = ParagraphSuggestionCache()
        #expect(await cache.lookup(makeKey(hash: 1)) == nil)
    }

    @Test func upsertThenLookupRoundtrips() async {
        let cache = ParagraphSuggestionCache()
        let sug = makeSuggestion()
        await cache.upsert(makeKey(hash: 1), status: .active, suggestions: [sug])
        let entry = await cache.lookup(makeKey(hash: 1))
        #expect(entry?.status == .active)
        #expect(entry?.suggestions == [sug])
    }

    @Test func sameHashDifferentBundleIDsAreIsolated() async {
        let cache = ParagraphSuggestionCache()
        await cache.upsert(makeKey(bundle: "A", hash: 42), status: .active, suggestions: [makeSuggestion("a")])
        #expect(await cache.lookup(makeKey(bundle: "B", hash: 42)) == nil)
    }

    @Test func sameBundleIDSameHashFromDifferentCallersSharesEntry() async {
        let cache = ParagraphSuggestionCache()
        let sug = makeSuggestion("shared")
        await cache.upsert(makeKey(bundle: "A", hash: 42), status: .active, suggestions: [sug])
        let entry = await cache.lookup(makeKey(bundle: "A", hash: 42))
        #expect(entry?.suggestions == [sug])
    }

    // MARK: - Dismissal (INCR-07)

    @Test func markDismissedSetsStatusAndPreservesSuggestions() async {
        let cache = ParagraphSuggestionCache()
        let sugA = makeSuggestion("a")
        let sugB = makeSuggestion("b")
        let key = makeKey(hash: 1)
        await cache.upsert(key, status: .active, suggestions: [sugA, sugB])
        await cache.markDismissed(key)
        let entry = await cache.lookup(key)
        #expect(entry?.status == .dismissed)
        #expect(entry?.suggestions == [sugA, sugB])
    }

    @Test func markDismissedOnMissingKeyIsNoOp() async {
        let cache = ParagraphSuggestionCache()
        let key = makeKey(hash: 99)
        await cache.markDismissed(key)
        #expect(await cache.lookup(key) == nil)
    }

    @Test func dismissedEntryDoesNotResurfaceOnReLookup() async {
        let cache = ParagraphSuggestionCache()
        let key = makeKey(hash: 1)
        await cache.upsert(key, status: .active, suggestions: [makeSuggestion()])
        await cache.markDismissed(key)
        let first = await cache.lookup(key)
        let second = await cache.lookup(key)
        #expect(first?.status == .dismissed)
        #expect(second?.status == .dismissed)
    }

    // MARK: - LRU (INCR-10)

    @Test func lruEvictsOldestWhenCapExceeded() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let cache = ParagraphSuggestionCache(clock: clock, ttl: 10_000, maxEntriesPerBundle: 3)

        await cache.upsert(makeKey(hash: 1), status: .active, suggestions: [makeSuggestion("1")])
        clock.current = clock.current.addingTimeInterval(1)
        await cache.upsert(makeKey(hash: 2), status: .active, suggestions: [makeSuggestion("2")])
        clock.current = clock.current.addingTimeInterval(1)
        await cache.upsert(makeKey(hash: 3), status: .active, suggestions: [makeSuggestion("3")])
        clock.current = clock.current.addingTimeInterval(1)
        _ = await cache.lookup(makeKey(hash: 1)) // refresh h1
        clock.current = clock.current.addingTimeInterval(1)
        await cache.upsert(makeKey(hash: 4), status: .active, suggestions: [makeSuggestion("4")])

        #expect(await cache.lookup(makeKey(hash: 1)) != nil)
        #expect(await cache.lookup(makeKey(hash: 2)) == nil) // oldest
        #expect(await cache.lookup(makeKey(hash: 3)) != nil)
        #expect(await cache.lookup(makeKey(hash: 4)) != nil)
    }

    @Test func lruCapIsPerBundleID() async {
        let cache = ParagraphSuggestionCache(maxEntriesPerBundle: 2)
        await cache.upsert(makeKey(bundle: "A", hash: 1), status: .active, suggestions: [makeSuggestion("a1")])
        await cache.upsert(makeKey(bundle: "A", hash: 2), status: .active, suggestions: [makeSuggestion("a2")])
        await cache.upsert(makeKey(bundle: "B", hash: 3), status: .active, suggestions: [makeSuggestion("b3")])
        await cache.upsert(makeKey(bundle: "B", hash: 4), status: .active, suggestions: [makeSuggestion("b4")])

        #expect(await cache.lookup(makeKey(bundle: "A", hash: 1)) != nil)
        #expect(await cache.lookup(makeKey(bundle: "A", hash: 2)) != nil)
        #expect(await cache.lookup(makeKey(bundle: "B", hash: 3)) != nil)
        #expect(await cache.lookup(makeKey(bundle: "B", hash: 4)) != nil)
    }

    // MARK: - TTL (INCR-10)

    @Test func ttlEvictsExpiredEntriesOnInsert() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let cache = ParagraphSuggestionCache(clock: clock, ttl: 60, maxEntriesPerBundle: 1000)

        await cache.upsert(makeKey(hash: 1), status: .active, suggestions: [makeSuggestion("1")])
        clock.current = clock.current.addingTimeInterval(120)
        await cache.upsert(makeKey(hash: 2), status: .active, suggestions: [makeSuggestion("2")])

        #expect(await cache.lookup(makeKey(hash: 1)) == nil)
        #expect(await cache.lookup(makeKey(hash: 2))?.status == .active)
    }

    @Test func ttlDoesNotEvictFreshEntriesOnLookup() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let cache = ParagraphSuggestionCache(clock: clock, ttl: 60, maxEntriesPerBundle: 1000)

        await cache.upsert(makeKey(hash: 1), status: .active, suggestions: [makeSuggestion("1")])
        clock.current = clock.current.addingTimeInterval(120)

        // Lookup past TTL still returns entry — D-16: no lazy eviction on lookup.
        // Note: lookup touches lastAccessedAt to clock.now(), so h1 is fresh after this.
        #expect(await cache.lookup(makeKey(hash: 1)) != nil)

        // Jump past TTL again relative to the refreshed lastAccessedAt, then upsert.
        clock.current = clock.current.addingTimeInterval(120)
        await cache.upsert(makeKey(hash: 2), status: .active, suggestions: [makeSuggestion("2")])

        #expect(await cache.lookup(makeKey(hash: 1)) == nil)
    }

    @Test func ttlSweepRunsBeforeLruCap() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let cache = ParagraphSuggestionCache(clock: clock, ttl: 10, maxEntriesPerBundle: 2)

        await cache.upsert(makeKey(hash: 1), status: .active, suggestions: [makeSuggestion("1")])
        await cache.upsert(makeKey(hash: 2), status: .active, suggestions: [makeSuggestion("2")])
        clock.current = clock.current.addingTimeInterval(20)
        await cache.upsert(makeKey(hash: 3), status: .active, suggestions: [makeSuggestion("3")])

        #expect(await cache.lookup(makeKey(hash: 1)) == nil)
        #expect(await cache.lookup(makeKey(hash: 2)) == nil)
        #expect(await cache.lookup(makeKey(hash: 3))?.status == .active)
    }

    // MARK: - INCR-12 payload contract

    @Test func suggestionsAreStoredVerbatim() async {
        let cache = ParagraphSuggestionCache()
        let sug = LLMStyleSuggestion(
            category: .clarity,
            originalText: "  The cat, perhaps, sat on the mat.  ",
            revisedText: "The cat sat on the mat.",
            explanation: "trim filler",
            confidence: 9
        )
        let key = makeKey(hash: 1)
        await cache.upsert(key, status: .active, suggestions: [sug])
        let entry = await cache.lookup(key)
        #expect(entry?.suggestions.first?.originalText == "  The cat, perhaps, sat on the mat.  ")
        #expect(entry?.suggestions.first == sug)
    }

    // MARK: - Performance (INCR-13)

    @Test func lookupCompletesUnder1msOnLoadedCache() async {
        let cache = ParagraphSuggestionCache()
        for i in 0..<500 {
            await cache.upsert(makeKey(hash: UInt64(i)), status: .active,
                               suggestions: [makeSuggestion("\(i)")])
        }
        _ = await cache.lookup(makeKey(hash: 250)) // warm-up

        let start = Date()
        for _ in 0..<100 {
            _ = await cache.lookup(makeKey(hash: 250))
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed / 100.0 < 0.001)
    }
}
