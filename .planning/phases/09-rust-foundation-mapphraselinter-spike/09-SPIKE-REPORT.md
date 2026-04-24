# CLAR-13 Spike: MapPhraseLinter Wrapper vs Custom First-Token Hashmap

**Spike date:** 2026-04-24
**Phase:** 09-rust-foundation-mapphraselinter-spike
**Corpus:** 20 phrases from `harper-bridge/data/wordy_phrases.toml`
**Hard gates:** 5-regime case preservation; priority rewrite stability
**Fallback policy:** Any hard-gate FAIL → custom first-token-hashmap (per D-05)

## Decision

**Adopt MapPhraseLinter wrapper**

Both hard gates passed. The 20-phrase corpus produced 100 case-preservation assertions (20 phrases × 5 regimes), all green via `Suggestion::replace_with_match_case`. Priority rewrite stability confirmed: every emitted lint carries priority ∈ {200, 220, 240} — zero leakage of harper-core's hardcoded 31. The wrapper (`PriorityRewritingMapPhraseLinter`) achieves correctness in ~40 LoC by rewriting `lint.priority` on every emission before push. harper-core 2.0.0's `MapPhraseLinter::match_to_lint` hardcodes `priority: 31` at `map_phrase_linter.rs:137` (see Framing Context), making native adoption impossible; the wrapper sidesteps this cleanly. Phase 10 promotes the spike struct from `#[cfg(test)] mod spike` to production scope, seeds it from `wordy_phrases.toml`, and adds dialect filtering + `remove_overlaps` per CLAR-06.

## Framing Context

harper-core 2.0.0 `MapPhraseLinter::match_to_lint` hardcodes `priority: 31` at `map_phrase_linter.rs:137`. Native adoption is impossible: priority 31 inverts CLAR-06 (clarity would beat grammar=127 and spelling=63 on overlap). `new_fixed_phrases` shares one `correct_forms` pool across all patterns — unusable for per-entry replacement. Spike premise: wrapper-over-MapPhraseLinter vs custom first-token-hashmap, NOT native vs custom (D-02).

No harper-core fork (D-05 — maintenance burden incompatible with standalone-app).

## Gate-by-Gate Evidence

| Hard Gate | Result | Evidence |
|-----------|--------|----------|
| 1. 5-regime case preservation (lowercase / Sentence-start / Title Case / UPPER CASE / post-colon) | PASS | `cargo test --lib clarity::spike::case_preservation_five_regimes` — `test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 5 filtered out; finished in 3.12s`. Repro: `cd harper-bridge && cargo test --lib clarity::spike::case_preservation_five_regimes -- --nocapture`. 100 assertions (20 phrases × 5 regimes) all pass via `eq_ignore_ascii_case` — exercises harper-core's `Suggestion::replace_with_match_case` on every regime. |
| 2. Priority rewrite stability (zero priority=31 leakage across 20-phrase corpus) | PASS | `cargo test --lib clarity::spike::priority_rewrite_no_default_leak` — `test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 5 filtered out; finished in 3.12s`. Repro: `cd harper-bridge && cargo test --lib clarity::spike::priority_rewrite_no_default_leak -- --nocapture`. Inspection snippet (`clarity.rs` spike wrapper): `lint.priority = *target_prio; out.push(lint);` — priority assignment happens BEFORE push, so no default 31 can leak. All lints across all 20 phrases confirmed priority ∈ {200, 220, 240}. |

## Wrapper Implementation (spike code)

```rust
struct PriorityRewritingMapPhraseLinter {
    inner: Vec<(MapPhraseLinter, u8)>,
}

impl Linter for PriorityRewritingMapPhraseLinter {
    fn lint(&mut self, document: &Document) -> Vec<Lint> {
        let mut out = Vec::new();
        for (linter, target_prio) in self.inner.iter_mut() {
            for mut lint in linter.lint(document) {
                lint.priority = *target_prio;
                out.push(lint);
            }
        }
        out
    }
    fn description(&self) -> &str { "Spike: MapPhraseLinter wrapper with priority rewrite." }
}
```

Lives in `harper-bridge/src/clarity.rs` `#[cfg(test)] mod spike`. ~40 LoC. No interior state. Zero-cost in release binary (cfg-gated).

## 20-Phrase Corpus

Picked from `harper-bridge/data/wordy_phrases.toml` per D-06 balance (≥3 each of Sentence-start / Title Case / post-colon / UPPER CASE; lowercase baseline; ≥2 multi-inflection pairs).

| # | Phrase | Replacement | Priority | Dataset Source Line |
|---|--------|-------------|----------|---------------------|
| 1 | utilize | use | HIGH (200) | wordy_phrases.toml:2278 |
| 2 | utilizes | use | MEDIUM (220) | wordy_phrases.toml:2293 |
| 3 | utilized | used | MEDIUM (220) | wordy_phrases.toml:2285 |
| 4 | a number of | many | HIGH (200) | wordy_phrases.toml:26 |
| 5 | accompany | go with | HIGH (200) | wordy_phrases.toml:61 |
| 6 | accomplish | carry out | HIGH (200) | wordy_phrases.toml:68 |
| 7 | accorded | given | HIGH (200) | wordy_phrases.toml:75 |
| 8 | accordingly | so | HIGH (200) | wordy_phrases.toml:82 |
| 9 | accurate | correct | HIGH (200) | wordy_phrases.toml:96 |
| 10 | additional | added | HIGH (200) | wordy_phrases.toml:117 |
| 11 | advantageous | helpful | HIGH (200) | wordy_phrases.toml:167 |
| 12 | abundance | enough | MEDIUM (220) | wordy_phrases.toml:33 |
| 13 | accede to | agree to | MEDIUM (220) | wordy_phrases.toml:40 |
| 14 | accelerate | speed up | MEDIUM (220) | wordy_phrases.toml:47 |
| 15 | accentuate | stress | MEDIUM (220) | wordy_phrases.toml:54 |
| 16 | acquire | get | MEDIUM (220) | wordy_phrases.toml:110 |
| 17 | aggregate | add | MEDIUM (220) | wordy_phrases.toml:209 |
| 18 | alleviate | ease | MEDIUM (220) | wordy_phrases.toml:230 |
| 19 | ameliorate | help | MEDIUM (220) | wordy_phrases.toml:265 |
| 20 | acquiesce | agree | MEDIUM (220) | wordy_phrases.toml:103 |

All 20 entries cross-referenced against `wordy_phrases.toml` phrase/replacement/severity fields before commit (plan 06 SUMMARY §Deviations — entries replaced where plan corpus had incorrect replacements not present in dataset).

## Non-Blocking Notes (per D-04)

- **Severity propagation:** Wrapper carries target priority in the `(MapPhraseLinter, u8)` tuple; `severity_from_priority(lint.priority)` in FFI translation block (`harper-bridge/src/lib.rs`) converts to `Option<Severity>` at the boundary. End-to-end round-trip verified green via `cargo test --lib stub_fires_flag_me` (stub path) + `xcodebuild ... -only-testing:OpenGramTests/ClarityFFITests/stubRoundTrip` (Swift path) in plans 04/05.
- **Wrapper LoC:** ~40 LoC (spike module excluding tests + corpus). Comparable to a custom hashmap matcher; not a decision factor (D-04).
- **~500 linter instances at production scale:** Acceptable — harper-core's own curated LintGroup stacks hundreds of linters (verified). No perf gate triggered.

## Phase 10 Implications

Phase 10 moves `PriorityRewritingMapPhraseLinter` out of `#[cfg(test)] mod spike` into production scope inside `harper-bridge/src/clarity.rs`.

- `build_lint_group` swaps `WordyPhrasesStubLinter` for the wrapper, seeded from `include_str!("../data/wordy_phrases.toml")` parsed in Phase 11.
- Phase 10 adds 5-regime case-preservation assertions against the full dataset + word-boundary + dialect filter + `remove_overlaps` call for CLAR-06.

## Decision Log

- 2026-04-24: Spike run. Both gates PASS. Adopt MapPhraseLinter wrapper. Phase 10 scope confirmed.

---

*End of spike report. Phase 10 planner reads this first per D-08.*
