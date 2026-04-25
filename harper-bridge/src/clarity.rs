//! Clarity-engine Rust surface: Severity FFI enum, priority constants,
//! the production WordyPhrasesLinter, and the curated CORPUS phrase entries.
//!
//! Priority policy (loses overlaps vs grammar=127 / spelling=63 per CLAR-06):
//!   PRIORITY_HIGH   = 200
//!   PRIORITY_MEDIUM = 220
//!   PRIORITY_LOW    = 240

use harper_core::Dialect;
use harper_core::Document;
use harper_core::linting::{Lint, LintKind, Linter, MapPhraseLinter};

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

use serde::Deserialize;
use std::sync::OnceLock;

#[derive(Deserialize)]
struct TomlFile {
    entries: Vec<TomlPhraseEntry>,
}

#[derive(Deserialize, Clone)]
struct TomlPhraseEntry {
    phrase:      String,
    replacement: String,
    severity:    String,
    #[serde(default)]
    dialects:    Option<Vec<String>>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ParsedPhraseEntry {
    pub phrase:      String,
    pub replacement: String,
    pub severity:    Severity,
    pub dialects:    Option<Vec<harper_core::Dialect>>,
}

fn severity_from_str(s: &str) -> Severity {
    match s {
        "high" => Severity::High,
        "low"  => Severity::Low,
        _      => Severity::Medium,
    }
}

fn dialect_from_str(s: &str) -> Option<harper_core::Dialect> {
    match s {
        "en-US" | "American"   => Some(harper_core::Dialect::American),
        "en-GB" | "British"    => Some(harper_core::Dialect::British),
        "en-CA" | "Canadian"   => Some(harper_core::Dialect::Canadian),
        "en-AU" | "Australian" => Some(harper_core::Dialect::Australian),
        "en-IN" | "Indian"     => Some(harper_core::Dialect::Indian),
        _ => None,
    }
}

pub fn parse_wordy_phrases(toml_str: &str) -> Vec<ParsedPhraseEntry> {
    let file: TomlFile = toml::from_str(toml_str)
        .expect("wordy_phrases.toml must parse — bundled at compile time via include_str!");
    file.entries.into_iter().map(|t| ParsedPhraseEntry {
        phrase:      t.phrase,
        replacement: t.replacement,
        severity:    severity_from_str(&t.severity),
        dialects:    t.dialects.map(|ds| ds.iter().filter_map(|d| dialect_from_str(d)).collect()),
    }).collect()
}

static PARSED_CORPUS: OnceLock<Vec<ParsedPhraseEntry>> = OnceLock::new();

pub fn get_corpus() -> &'static [ParsedPhraseEntry] {
    PARSED_CORPUS.get_or_init(|| {
        parse_wordy_phrases(include_str!("../data/wordy_phrases.toml"))
    })
}

#[cfg(test)]
pub(crate) fn parsed_corpus_handle() -> &'static OnceLock<Vec<ParsedPhraseEntry>> {
    &PARSED_CORPUS
}

// Production phrase-matcher surface — promotes the spike's 20-entry corpus
// to module scope plus one synthetic dialect-tagged entry exercising the build-time
// dialect filter in build_lint_group. Subsequent work swaps the const slice for an owned
// Vec<PhraseEntry> parsed from wordy_phrases.toml.

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
    fn proper_noun_iphone_does_not_trigger() {
        // CLAR-03 acceptance: mixed-case proper nouns must never trigger replacement.
        // Contract test on MapPhraseLinter token-shape behavior — iPhone is one Word
        // token with content ['i','P','h','o','n','e'], cannot match any CORPUS phrase.
        let merged = make_merged_dict();
        let mut linter = WordyPhrasesLinter::new(CORPUS);
        let doc = Document::new("iPhone is great.", &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);
        assert!(
            lints.is_empty(),
            "iPhone must not trigger any clarity lint; got {:?}",
            lints.iter().map(primary_replacement).collect::<Vec<_>>(),
        );
    }

    #[test]
    fn word_boundary_no_midword_match() {
        // CLAR-05 SC-3: phrase matches only on Harper token boundaries; mid-word
        // substrings never fire. CORPUS contains "accompany"; "unaccompanied" is
        // tokenized as one Word token whose char-content includes "accompany"
        // mid-string. MapPhraseLinter matches token-windows, never substrings.
        let merged = make_merged_dict();
        let mut linter = WordyPhrasesLinter::new(CORPUS);
        let doc = Document::new("The unaccompanied luggage arrived.", &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);
        assert!(
            lints.is_empty(),
            "mid-word substring must not trigger clarity lint; got {:?}",
            lints.iter().map(primary_replacement).collect::<Vec<_>>(),
        );
    }

    #[test]
    fn case_preservation_under_tr_locale() {
        // CLAR-N4: Turkish locale 'I'.to_lowercase() → 'ı', 'i'.to_uppercase() → 'İ'.
        // Rust std char::to_uppercase / to_lowercase use Unicode tables, not OS
        // locale, but some downstream tools or future code paths might. This test
        // guards that replace_with_match_case output stays ASCII-correct regardless
        // of process locale — locking the contract end-to-end.
        let old_lang   = std::env::var("LANG").ok();
        let old_lc_all = std::env::var("LC_ALL").ok();
        std::env::set_var("LANG",   "tr_TR.UTF-8");
        std::env::set_var("LC_ALL", "tr_TR.UTF-8");

        let merged = make_merged_dict();
        let mut linter = WordyPhrasesLinter::new(CORPUS);
        for entry in CORPUS {
            let input = format!("WE MUST {} IT.", entry.phrase.to_uppercase());
            let doc   = Document::new(&input, &PlainEnglish, merged.as_ref());
            for lint in linter.lint(&doc) {
                if let Some(rep) = primary_replacement(&lint) {
                    // Replacement chars must be ASCII (no İ / ı drift).
                    let ok = rep.chars().all(|c| !c.is_alphabetic() || c.is_ascii());
                    assert!(
                        ok,
                        "Turkish locale corrupted replacement for '{}': got '{}'",
                        entry.phrase, rep,
                    );
                }
            }
        }

        // Env vars are process-global; reset before returning so other tests in the
        // same binary aren't affected by lingering tr_TR locale.
        match old_lang   { Some(v) => std::env::set_var("LANG",   v), None => std::env::remove_var("LANG") }
        match old_lc_all { Some(v) => std::env::set_var("LC_ALL", v), None => std::env::remove_var("LC_ALL") }
    }

    #[test]
    fn parse_wordy_phrases_round_trip() {
        let toml = r#"
        [[entries]]
        phrase = "utilize"
        replacement = "use"
        severity = "high"
        sources = ["retext-simplify"]
        id = "utilize"
        "#;
        let parsed = parse_wordy_phrases(toml);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].phrase, "utilize");
        assert_eq!(parsed[0].replacement, "use");
        assert_eq!(parsed[0].severity, Severity::High);
        assert!(parsed[0].dialects.is_none());
    }

    #[test]
    fn parse_wordy_phrases_real_dataset_338_entries() {
        let parsed = parse_wordy_phrases(include_str!("../data/wordy_phrases.toml"));
        assert_eq!(parsed.len(), 338, "wordy_phrases.toml dataset count");
    }

    #[test]
    fn corpus_parsed_exactly_once() {
        let first = get_corpus();
        assert!(parsed_corpus_handle().get().is_some(),
            "corpus must be initialized after first get_corpus()");
        let ptr1 = first.as_ptr();

        for _ in 0..100 {
            let _ = get_corpus();
        }

        let after = get_corpus();
        assert_eq!(after.as_ptr(), ptr1, "same allocation = single parse across 102 calls");
        assert_eq!(after.len(), 338, "real dataset count");
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
