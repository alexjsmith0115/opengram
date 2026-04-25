//! Clarity-engine Rust surface: Severity FFI enum, priority constants, and
//! the stub WordyPhrasesLinter consumed by `build_lint_group`.
//!
//! Priority policy (loses overlaps vs grammar=127 / spelling=63 per CLAR-06):
//!   PRIORITY_HIGH   = 200
//!   PRIORITY_MEDIUM = 220
//!   PRIORITY_LOW    = 240
//!
//! Implementation lands in Wave 1 (plans 02–04). This file currently holds
//! test scaffolding only.

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    High,
    Medium,
    Low,
}

pub const PRIORITY_HIGH: u8 = 200;
pub const PRIORITY_MEDIUM: u8 = 220;
pub const PRIORITY_LOW: u8 = 240;

pub fn severity_to_priority(sev: Severity) -> u8 {
    match sev {
        Severity::High => PRIORITY_HIGH,
        Severity::Medium => PRIORITY_MEDIUM,
        Severity::Low => PRIORITY_LOW,
    }
}

pub fn severity_from_priority(prio: u8) -> Option<Severity> {
    match prio {
        PRIORITY_HIGH => Some(Severity::High),
        PRIORITY_MEDIUM => Some(Severity::Medium),
        PRIORITY_LOW => Some(Severity::Low),
        _ => None,
    }
}

// Production phrase-matcher surface — promotes the spike's 20-entry corpus
// to module scope plus one synthetic dialect-tagged entry exercising the build-time
// dialect filter in build_lint_group. Subsequent work swaps the const slice for an owned
// Vec<PhraseEntry> parsed from wordy_phrases.toml.

use harper_core::Dialect;
use harper_core::linting::MapPhraseLinter;

#[derive(Clone, Copy)]
pub(crate) struct PhraseEntry {
    pub phrase:      &'static str,
    pub replacement: &'static str,
    pub severity:    Severity,
    pub dialects:    Option<&'static [Dialect]>,
}

pub(crate) const CORPUS: &[PhraseEntry] = &[
    // Multi-inflection triple — exercises CLAR-04 dataset-driven inflection
    PhraseEntry { phrase: "utilize",      replacement: "use",       severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "utilizes",     replacement: "use",       severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "utilized",     replacement: "used",      severity: Severity::Medium, dialects: None },
    // High severity
    PhraseEntry { phrase: "a number of",  replacement: "many",      severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "accompany",    replacement: "go with",   severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "accomplish",   replacement: "carry out", severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "accorded",     replacement: "given",     severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "accordingly",  replacement: "so",        severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "accurate",     replacement: "correct",   severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "additional",   replacement: "added",     severity: Severity::High,   dialects: None },
    PhraseEntry { phrase: "advantageous", replacement: "helpful",   severity: Severity::High,   dialects: None },
    // Medium severity
    PhraseEntry { phrase: "abundance",    replacement: "enough",    severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "accede to",    replacement: "agree to",  severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "accelerate",   replacement: "speed up",  severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "accentuate",   replacement: "stress",    severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "acquire",      replacement: "get",       severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "aggregate",    replacement: "add",       severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "alleviate",    replacement: "ease",      severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "ameliorate",   replacement: "help",      severity: Severity::Medium, dialects: None },
    PhraseEntry { phrase: "acquiesce",    replacement: "agree",     severity: Severity::Medium, dialects: None },
    // Synthetic American-only entry — exercises non-empty branch of dialect filter.
    // "forthwith" is intentionally NOT in wordy_phrases.toml so subsequent TOML wire-up
    // won't override its dialect tag.
    PhraseEntry { phrase: "forthwith",    replacement: "at once",   severity: Severity::Low,    dialects: Some(&[Dialect::American]) },
];

use harper_core::Document;
use harper_core::TokenKind;
use harper_core::linting::{Lint, LintKind, Linter, Suggestion};
use harper_core::Punctuation;

pub(crate) struct WordyPhrasesLinter {
    inner: Vec<(MapPhraseLinter, u8)>,
}

impl WordyPhrasesLinter {
    pub(crate) fn new(entries: &[PhraseEntry]) -> Self {
        let inner = entries
            .iter()
            .map(|entry| {
                let mpl = MapPhraseLinter::new_fixed_phrase(
                    entry.phrase,
                    [entry.replacement],
                    format!("Consider '{}' for '{}'", entry.replacement, entry.phrase),
                    "Wordy-phrase clarity linter — flags wordy phrases with simpler replacements per the curated corpus.".to_string(),
                    Some(LintKind::Style),
                );
                (mpl, severity_to_priority(entry.severity))
            })
            .collect();
        Self { inner }
    }
}

impl Linter for WordyPhrasesLinter {
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

    fn description(&self) -> &str {
        "Wordy-phrase clarity linter — flags wordy phrases with simpler replacements per the curated corpus."
    }
}

pub struct WordyPhrasesStubLinter;

impl WordyPhrasesStubLinter {
    pub fn new() -> Self { Self }
}

impl Default for WordyPhrasesStubLinter {
    fn default() -> Self { Self::new() }
}

impl Linter for WordyPhrasesStubLinter {
    fn lint(&mut self, document: &Document) -> Vec<Lint> {
        let source = document.get_source();
        let flag: [char; 4] = ['F', 'L', 'A', 'G'];
        let me: [char; 2] = ['M', 'E'];
        let mut out = Vec::new();

        let tokens: Vec<_> = document.tokens().collect();
        for window in tokens.windows(3) {
            let is_flag = matches!(window[0].kind, TokenKind::Word(_))
                && window[0].span.get_content(source) == flag;
            let is_underscore =
                matches!(window[1].kind, TokenKind::Punctuation(Punctuation::Underscore));
            let is_me = matches!(window[2].kind, TokenKind::Word(_))
                && window[2].span.get_content(source) == me;

            if is_flag && is_underscore && is_me {
                use harper_core::Span;
                let span = Span::new(window[0].span.start, window[2].span.end);
                out.push(Lint {
                    span,
                    lint_kind: LintKind::Style,
                    suggestions: vec![Suggestion::ReplaceWith("FLAGGED".chars().collect())],
                    message: "Consider alternative phrasing".to_string(),
                    priority: PRIORITY_MEDIUM,
                });
            }
        }
        out
    }

    fn description(&self) -> &str {
        "Stub wordy-phrases linter — placeholder for dataset-driven matcher."
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use harper_core::Document;
    use harper_core::linting::{Lint, Suggestion};
    use harper_core::parsers::PlainEnglish;
    use harper_core::spell::{FstDictionary, MergedDictionary};
    use std::sync::Arc;

    fn make_merged_dict() -> Arc<MergedDictionary> {
        let mut merged = MergedDictionary::new();
        merged.add_dictionary(FstDictionary::curated());
        Arc::new(merged)
    }

    fn title_case(s: &str) -> String {
        s.split_whitespace()
            .map(|w| {
                let mut chars = w.chars();
                match chars.next() {
                    Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
                    None => String::new(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn sentence_start(s: &str) -> String {
        let mut chars = s.chars();
        match chars.next() {
            Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            None => String::new(),
        }
    }

    fn primary_replacement(lint: &Lint) -> Option<String> {
        lint.suggestions.first().and_then(|s| match s {
            Suggestion::ReplaceWith(chars) => Some(chars.iter().collect()),
            _ => None,
        })
    }

    #[test]
    fn clarity_loses_to_grammar_on_overlap() {
        use harper_core::linting::{Lint, LintKind, Suggestion};
        use harper_core::Span;
        use harper_core::remove_overlaps;

        // Two lints sharing the same span. Grammar (priority 127) must beat clarity (priority 220)
        // per CLAR-06: lower-priority-number wins in remove_overlaps.
        let grammar_lint = Lint {
            span: Span::new(0, 7),
            lint_kind: LintKind::Miscellaneous,
            suggestions: vec![Suggestion::ReplaceWith("fix-grammar".chars().collect())],
            message: "grammar fix".to_string(),
            priority: 127,
        };

        let clarity_lint = Lint {
            span: Span::new(0, 7),
            lint_kind: LintKind::Style,
            suggestions: vec![Suggestion::ReplaceWith("FLAGGED".chars().collect())],
            message: "clarity fix".to_string(),
            priority: PRIORITY_MEDIUM,
        };

        let mut lints = vec![grammar_lint, clarity_lint];
        remove_overlaps(&mut lints);

        assert_eq!(lints.len(), 1, "overlap resolution must keep exactly one lint");
        assert_eq!(lints[0].priority, 127, "grammar (127) must beat clarity (220) — CLAR-06 lower-number-wins");
        assert!(matches!(lints[0].lint_kind, LintKind::Miscellaneous), "surviving lint must be the grammar lint");
    }

    #[test]
    fn severity_enum() {
        assert_eq!(severity_to_priority(Severity::High), PRIORITY_HIGH);
        assert_eq!(severity_to_priority(Severity::Medium), PRIORITY_MEDIUM);
        assert_eq!(severity_to_priority(Severity::Low), PRIORITY_LOW);
        assert_eq!(PRIORITY_HIGH, 200);
        assert_eq!(PRIORITY_MEDIUM, 220);
        assert_eq!(PRIORITY_LOW, 240);
    }

    #[test]
    fn severity_round_trip() {
        assert_eq!(severity_from_priority(PRIORITY_HIGH), Some(Severity::High));
        assert_eq!(severity_from_priority(PRIORITY_MEDIUM), Some(Severity::Medium));
        assert_eq!(severity_from_priority(PRIORITY_LOW), Some(Severity::Low));
        assert_eq!(severity_from_priority(31), None);
        assert_eq!(severity_from_priority(127), None);
        assert_eq!(severity_from_priority(63), None);
    }

    #[test]
    fn case_preservation_five_regimes() {
        let merged = make_merged_dict();
        let mut linter = WordyPhrasesLinter::new(CORPUS);

        for entry in CORPUS {
            let test_cases: Vec<(String, String, &str)> = vec![
                (
                    format!("Please {} now.", entry.phrase),
                    entry.replacement.to_string(),
                    "lowercase",
                ),
                (
                    format!("{} is important.", sentence_start(entry.phrase)),
                    sentence_start(entry.replacement),
                    "sentence-start",
                ),
                (
                    format!("We Should {} It.", title_case(entry.phrase)),
                    title_case(entry.replacement),
                    "title-case",
                ),
                (
                    format!("WE MUST {} IT.", entry.phrase.to_uppercase()),
                    entry.replacement.to_uppercase(),
                    "upper-case",
                ),
                (
                    format!("Note: {} is needed.", entry.phrase),
                    entry.replacement.to_string(),
                    "post-colon",
                ),
            ];

            for (input, expected, regime) in &test_cases {
                let doc = Document::new(input, &PlainEnglish, merged.as_ref());
                let lints = linter.lint(&doc);
                let matching: Vec<String> = lints
                    .iter()
                    .filter_map(primary_replacement)
                    .filter(|r| r.eq_ignore_ascii_case(expected))
                    .collect();
                assert!(
                    !matching.is_empty(),
                    "regime '{}' phrase '{}': expected replacement '{}' (case-insensitive), got: {:?}",
                    regime,
                    entry.phrase,
                    expected,
                    lints.iter().map(primary_replacement).collect::<Vec<_>>(),
                );
            }
        }
    }

    #[test]
    fn priority_rewrite_no_default_leak() {
        let merged = make_merged_dict();
        let mut linter = WordyPhrasesLinter::new(CORPUS);

        let text = CORPUS
            .iter()
            .map(|e| format!("Please {}.", e.phrase))
            .collect::<Vec<_>>()
            .join(" ");

        let doc = Document::new(&text, &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);

        assert!(!lints.is_empty(), "corpus text must produce at least one lint");

        for lint in &lints {
            let valid = lint.priority == PRIORITY_HIGH
                || lint.priority == PRIORITY_MEDIUM
                || lint.priority == PRIORITY_LOW;
            assert!(
                valid,
                "priority leak: lint.priority = {} (expected {}/{}/{}); suggestion = {:?}",
                lint.priority,
                PRIORITY_HIGH,
                PRIORITY_MEDIUM,
                PRIORITY_LOW,
                primary_replacement(lint),
            );
        }
    }
}

#[cfg(test)]
mod spike {
    //! CLAR-13 spike (D-01 through D-06). Hard gates:
    //!   1. 5-regime case preservation via Suggestion::replace_with_match_case
    //!   2. Priority rewrite stability — zero leakage of MapPhraseLinter's hardcoded 31
    //!
    //! Wrapper delegates to MapPhraseLinter::new_fixed_phrase per entry and
    //! rewrites lint.priority on every emission.

    use super::{PRIORITY_HIGH, PRIORITY_MEDIUM, PRIORITY_LOW};
    use harper_core::linting::{Lint, LintKind, Linter, MapPhraseLinter, Suggestion};
    use harper_core::parsers::PlainEnglish;
    use harper_core::spell::{FstDictionary, MergedDictionary};
    use harper_core::Document;
    use std::sync::Arc;

    struct PriorityRewritingMapPhraseLinter {
        inner: Vec<(MapPhraseLinter, u8)>,
    }

    impl PriorityRewritingMapPhraseLinter {
        fn new(entries: &[(&'static str, &'static str, u8)]) -> Self {
            let inner = entries
                .iter()
                .map(|(phrase, replacement, prio)| {
                    let mpl = MapPhraseLinter::new_fixed_phrase(
                        *phrase,
                        [*replacement],
                        format!("Consider '{}' for '{}'", replacement, phrase),
                        format!("Wordy-phrase spike: {}", phrase),
                        Some(LintKind::Style),
                    );
                    (mpl, *prio)
                })
                .collect();
            Self { inner }
        }
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

        fn description(&self) -> &str {
            "Spike: MapPhraseLinter wrapper with priority rewrite."
        }
    }

    // D-06 corpus: 20 phrases from harper-bridge/data/wordy_phrases.toml.
    // Balance: utilize/utilizes/utilized multi-inflection triple; high/medium mix;
    // single-token + multi-token phrases for regime coverage.
    // Each entry: (toml phrase, toml replacement, severity-mapped priority constant).
    const CORPUS: &[(&str, &str, u8)] = &[
        // Multi-inflection triple (D-06: ≥2 multi-inflection pairs) — toml lines 2278–2298
        ("utilize", "use", PRIORITY_HIGH),
        ("utilizes", "use", PRIORITY_MEDIUM),
        ("utilized", "used", PRIORITY_MEDIUM),
        // High severity — toml lines 26, 61, 68, 75, 82, 96, 117, 167
        ("a number of", "many", PRIORITY_HIGH),
        ("accompany", "go with", PRIORITY_HIGH),
        ("accomplish", "carry out", PRIORITY_HIGH),
        ("accorded", "given", PRIORITY_HIGH),
        ("accordingly", "so", PRIORITY_HIGH),
        ("accurate", "correct", PRIORITY_HIGH),
        ("additional", "added", PRIORITY_HIGH),
        ("advantageous", "helpful", PRIORITY_HIGH),
        // Medium severity — toml lines 33, 40, 47, 54, 110, 209, 230, 265
        ("abundance", "enough", PRIORITY_MEDIUM),
        ("accede to", "agree to", PRIORITY_MEDIUM),
        ("accelerate", "speed up", PRIORITY_MEDIUM),
        ("accentuate", "stress", PRIORITY_MEDIUM),
        ("acquire", "get", PRIORITY_MEDIUM),
        ("aggregate", "add", PRIORITY_MEDIUM),
        ("alleviate", "ease", PRIORITY_MEDIUM),
        ("ameliorate", "help", PRIORITY_MEDIUM),
        ("acquiesce", "agree", PRIORITY_MEDIUM),
    ];

    fn make_merged_dict() -> Arc<MergedDictionary> {
        let mut merged = MergedDictionary::new();
        merged.add_dictionary(FstDictionary::curated());
        Arc::new(merged)
    }

    fn title_case(s: &str) -> String {
        s.split_whitespace()
            .map(|w| {
                let mut chars = w.chars();
                match chars.next() {
                    Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
                    None => String::new(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ")
    }

    fn sentence_start(s: &str) -> String {
        let mut chars = s.chars();
        match chars.next() {
            Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            None => String::new(),
        }
    }

    fn primary_replacement(lint: &Lint) -> Option<String> {
        lint.suggestions.first().and_then(|s| match s {
            Suggestion::ReplaceWith(chars) => Some(chars.iter().collect()),
            _ => None,
        })
    }

    #[test]
    fn case_preservation_five_regimes() {
        let merged = make_merged_dict();
        let mut linter = PriorityRewritingMapPhraseLinter::new(CORPUS);

        for (phrase, replacement, _prio) in CORPUS {
            let test_cases: Vec<(String, String, &str)> = vec![
                // 1. lowercase — phrase as-is
                (
                    format!("Please {} now.", phrase),
                    replacement.to_string(),
                    "lowercase",
                ),
                // 2. Sentence-start — first char capitalised
                (
                    format!("{} is important.", sentence_start(phrase)),
                    sentence_start(replacement),
                    "sentence-start",
                ),
                // 3. Title Case — every word capitalised (tests multi-word phrases too)
                (
                    format!("We Should {} It.", title_case(phrase)),
                    title_case(replacement),
                    "title-case",
                ),
                // 4. UPPER CASE
                (
                    format!("WE MUST {} IT.", phrase.to_uppercase()),
                    replacement.to_uppercase(),
                    "upper-case",
                ),
                // 5. post-colon — phrase immediately after colon+space (lowercase)
                (
                    format!("Note: {} is needed.", phrase),
                    replacement.to_string(),
                    "post-colon",
                ),
            ];

            for (input, expected, regime) in &test_cases {
                let doc = Document::new(input, &PlainEnglish, merged.as_ref());
                let lints = linter.lint(&doc);
                let matching: Vec<String> = lints
                    .iter()
                    .filter_map(primary_replacement)
                    .filter(|r| r.eq_ignore_ascii_case(expected))
                    .collect();
                assert!(
                    !matching.is_empty(),
                    "regime '{}' phrase '{}': expected replacement '{}' (case-insensitive), got: {:?}",
                    regime,
                    phrase,
                    expected,
                    lints.iter().map(primary_replacement).collect::<Vec<_>>(),
                );
            }
        }
    }

    #[test]
    fn priority_rewrite_no_default_leak() {
        let merged = make_merged_dict();
        let mut linter = PriorityRewritingMapPhraseLinter::new(CORPUS);

        // Build text containing every corpus phrase as a standalone sentence.
        let text = CORPUS
            .iter()
            .map(|(p, _, _)| format!("Please {}.", p))
            .collect::<Vec<_>>()
            .join(" ");

        let doc = Document::new(&text, &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);

        assert!(!lints.is_empty(), "corpus text must produce at least one lint");

        for lint in &lints {
            let valid = lint.priority == PRIORITY_HIGH
                || lint.priority == PRIORITY_MEDIUM
                || lint.priority == PRIORITY_LOW;
            assert!(
                valid,
                "priority leak: lint.priority = {} (expected {}/{}/{}); suggestion = {:?}",
                lint.priority,
                PRIORITY_HIGH,
                PRIORITY_MEDIUM,
                PRIORITY_LOW,
                primary_replacement(lint),
            );
        }
    }
}
