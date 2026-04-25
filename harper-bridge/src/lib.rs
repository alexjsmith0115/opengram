use std::sync::{Arc, Mutex};

use harper_core::linting::{LintGroup, LintKind, Linter, Suggestion};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::{FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{DictWordMetadata, Dialect, DialectFlags, Document};
use clarity::{Severity, WordyPhrasesLinter, severity_from_priority, get_corpus, ParsedPhraseEntry};

uniffi::setup_scaffolding!();
mod clarity;

/// D-03 spelling/grammar + D-32 clarity routing: Clarity emitted when LintKind::Style + priority ∈ {200,220,240}.
#[derive(uniffi::Enum)]
pub enum SuggestionCategory {
    Spelling,
    GrammarPunctuation,
    Clarity,
}

/// Carries all Harper replacements so callers can decide presentation (D-01).
/// Char offsets index into the Swift String.unicodeScalars view.
/// `severity` populated only for Clarity category; None for spelling + grammar/punctuation per D-10.
#[derive(uniffi::Record)]
pub struct GrammarSuggestion {
    pub start_char: u32,
    pub end_char: u32,
    pub message: String,
    pub primary_replacement: Option<String>,
    pub all_replacements: Vec<String>,
    pub category: SuggestionCategory,
    pub priority: u8,
    pub severity: Option<Severity>,
}

/// UniFFI wraps objects in Arc, so interior mutability via Mutex is required
/// since LintGroup::lint and MutableDictionary both need &mut self.
#[derive(uniffi::Object)]
pub struct HarperChecker {
    inner: Mutex<HarperCheckerInner>,
}

struct HarperCheckerInner {
    linter: LintGroup,
    merged_dict: Arc<MergedDictionary>,
    user_dict: MutableDictionary,
    user_words: Vec<String>,
    dialect: Dialect,
}

// LintGroup contains Box<dyn Linter> and Lrc (non-Send types).
// Safety: Mutex<HarperCheckerInner> ensures exclusive access -- no concurrent
// mutation is possible. The Swift-side actor provides the same single-threaded
// contract, making this safe in practice.
unsafe impl Send for HarperCheckerInner {}
unsafe impl Sync for HarperCheckerInner {}

#[uniffi::export]
impl HarperChecker {
    #[uniffi::constructor]
    pub fn new(dialect_abbr: String, user_words: Vec<String>) -> Self {
        let dialect = parse_dialect(&dialect_abbr);
        let mut user_dict = MutableDictionary::new();
        let dialect_meta = DictWordMetadata {
            dialects: DialectFlags::all(),
            ..Default::default()
        };
        user_dict.extend_words(user_words.iter().map(|w| {
            (w.chars().collect::<Vec<char>>(), dialect_meta.clone())
        }));

        let merged = build_merged_dict(&user_dict);

        Self {
            inner: Mutex::new(HarperCheckerInner {
                linter: build_lint_group(merged.clone(), dialect),
                merged_dict: merged,
                user_dict,
                user_words: user_words.clone(),
                dialect,
            }),
        }
    }

    pub fn check(&self, text: String) -> Vec<GrammarSuggestion> {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        let document = Document::new(&text, &PlainEnglish, inner.merged_dict.as_ref());
        let lints = inner.linter.lint(&document);

        lints
            .into_iter()
            .map(|lint| {
                let span = lint.span;
                let all_replacements: Vec<String> = lint
                    .suggestions
                    .iter()
                    .filter_map(|s| match s {
                        Suggestion::ReplaceWith(chars) => Some(chars.iter().collect()),
                        Suggestion::InsertAfter(chars) => Some(chars.iter().collect()),
                        Suggestion::Remove => Some(String::new()),
                    })
                    .collect();
                let primary_replacement = all_replacements.first().cloned();

                let (category, severity) = match (lint.lint_kind, severity_from_priority(lint.priority)) {
                    (LintKind::Spelling, _) => (SuggestionCategory::Spelling, None),
                    (LintKind::Style, Some(sev)) => (SuggestionCategory::Clarity, Some(sev)),
                    _ => (SuggestionCategory::GrammarPunctuation, None),
                };

                GrammarSuggestion {
                    start_char: span.start as u32,
                    end_char: span.end as u32,
                    message: lint.message,
                    primary_replacement,
                    all_replacements,
                    category,
                    priority: lint.priority,
                    severity,
                }
            })
            .collect()
    }

    /// Adds a word to the user dictionary, rebuilds the linter so the word is
    /// recognized immediately, and returns the full updated word list for Swift
    /// to persist to dictionary.txt (D-06).
    pub fn add_to_dictionary(&self, word: String) -> Vec<String> {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        let dialect_meta = DictWordMetadata {
            dialects: DialectFlags::all(),
            ..Default::default()
        };
        inner.user_dict.append_word_str(&word, dialect_meta);
        inner.user_words.push(word);

        let merged = build_merged_dict(&inner.user_dict);
        inner.linter = build_lint_group(merged.clone(), inner.dialect);
        inner.merged_dict = merged;

        inner.user_words.clone()
    }

    /// Enable/disable a named rule. Keys match FlatConfig rule names (GRAM-09).
    pub fn set_rule_enabled(&self, rule_key: String, enabled: bool) {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        inner.linter.config.set_rule_enabled(&rule_key, enabled);
    }
}

fn build_lint_group(merged: Arc<MergedDictionary>, dialect: Dialect) -> LintGroup {
    let applicable: Vec<ParsedPhraseEntry> = get_corpus()
        .iter()
        .filter(|e| match &e.dialects {
            None          => true,
            Some(allowed) => allowed.contains(&dialect),
        })
        .cloned()
        .collect();
    let mut group = LintGroup::new_curated(merged, dialect);
    group.add("WordyPhrases", WordyPhrasesLinter::new_from_parsed(&applicable));
    // Rules added via `add()` default to disabled in FlatConfig (unwrap_or(false)).
    group.config.set_rule_enabled("WordyPhrases", true);
    group
}

fn build_merged_dict(user_dict: &MutableDictionary) -> Arc<MergedDictionary> {
    let mut merged = MergedDictionary::new();
    merged.add_dictionary(FstDictionary::curated());
    merged.add_dictionary(Arc::new(user_dict.clone()));
    Arc::new(merged)
}

fn parse_dialect(abbr: &str) -> Dialect {
    match abbr {
        "GB" => Dialect::British,
        "CA" => Dialect::Canadian,
        "AU" => Dialect::Australian,
        "IN" => Dialect::Indian,
        _ => Dialect::American,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clarity::Severity;

    #[test]
    fn wordy_phrases_fires_corpus_entry() {
        let checker = HarperChecker::new("US".into(), vec![]);
        let out = checker.check("Please utilize this.".into());
        // CORPUS entry "utilize" → "use" with Severity::High → priority 200, category Clarity.
        let utilize_lints: Vec<&GrammarSuggestion> = out
            .iter()
            .filter(|s| s.primary_replacement.as_deref() == Some("use"))
            .collect();
        assert_eq!(utilize_lints.len(), 1, "must emit exactly one suggestion for 'utilize'");
        let s = utilize_lints[0];
        assert!(matches!(s.category, SuggestionCategory::Clarity), "category must be Clarity");
        assert!(matches!(s.severity, Some(Severity::High)), "utilize → High severity");
        assert_eq!(s.priority, 200, "High → PRIORITY_HIGH = 200");
        assert_eq!(s.primary_replacement.as_deref(), Some("use"));
    }

    #[test]
    fn clarity_linter_survives_dict_add_cycle() {
        let checker = HarperChecker::new("US".into(), vec![]);
        // Pre-dict-add: utilize → use fires.
        let pre = checker.check("Please utilize this.".into());
        let pre_count = pre.iter().filter(|s| s.primary_replacement.as_deref() == Some("use")).count();
        assert_eq!(pre_count, 1, "fires pre-dict-add");

        let _ = checker.add_to_dictionary("somenewword".into());

        // Post-dict-add: build_lint_group rebuilt; clarity linter still wired.
        let post = checker.check("Please utilize this.".into());
        let post_count = post.iter().filter(|s| s.primary_replacement.as_deref() == Some("use")).count();
        assert_eq!(post_count, 1, "STILL fires post-dict-add — CLAR-12 invariant");
    }

    #[test]
    fn dialect_filter_drops_non_matching() {
        // CLAR-15 / D-05 (STATE [10-04]): forthwith is intentionally absent from
        // wordy_phrases.toml; this test injects it locally to exercise the
        // dialect-filter branch of build_lint_group without contaminating prod data.
        use crate::clarity::{ParsedPhraseEntry, WordyPhrasesLinter};
        use harper_core::Dialect;
        use harper_core::Document;
        use harper_core::linting::Linter;
        use harper_core::parsers::PlainEnglish;
        use harper_core::spell::{FstDictionary, MergedDictionary};
        use std::sync::Arc;

        fn make_dict() -> Arc<MergedDictionary> {
            let mut m = MergedDictionary::new();
            m.add_dictionary(FstDictionary::curated());
            Arc::new(m)
        }

        let synthetic = ParsedPhraseEntry {
            phrase:      "forthwith".to_string(),
            replacement: "at once".to_string(),
            severity:    Severity::Low,
            dialects:    Some(vec![Dialect::American]),
        };

        // Inline replication of build_lint_group's dialect-filter branch:
        let dialects_us: Vec<ParsedPhraseEntry> = std::iter::once(synthetic.clone())
            .filter(|e| match &e.dialects {
                None => true,
                Some(allowed) => allowed.contains(&Dialect::American),
            }).collect();
        let dialects_gb: Vec<ParsedPhraseEntry> = std::iter::once(synthetic.clone())
            .filter(|e| match &e.dialects {
                None => true,
                Some(allowed) => allowed.contains(&Dialect::British),
            }).collect();

        assert_eq!(dialects_us.len(), 1, "American: synthetic forthwith retained");
        assert_eq!(dialects_gb.len(), 0, "British: synthetic forthwith dropped");

        // End-to-end: linter built from filtered American slice fires; British slice empty → 0 lints
        let mut linter_us = WordyPhrasesLinter::new_from_parsed(&dialects_us);
        let mut linter_gb = WordyPhrasesLinter::new_from_parsed(&dialects_gb);
        let doc = Document::new("Please forthwith now.", &PlainEnglish, make_dict().as_ref());
        let us_lints = linter_us.lint(&doc);
        let gb_lints = linter_gb.lint(&doc);
        let us_at_once = us_lints.iter().filter(|l| {
            l.suggestions.first().map(|s| matches!(s, harper_core::linting::Suggestion::ReplaceWith(c) if c.iter().collect::<String>() == "at once")).unwrap_or(false)
        }).count();
        assert_eq!(us_at_once, 1, "American: forthwith → at once fires once");
        assert_eq!(gb_lints.len(), 0, "British: filtered slice produces zero lints");
    }
}
