use std::sync::{Arc, Mutex};

use harper_core::linting::{LintGroup, LintKind, Linter, Suggestion};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::{FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{DictWordMetadata, Dialect, DialectFlags, Document};
use clarity::{Severity, WordyPhrasesStubLinter, severity_from_priority};

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
    let mut group = LintGroup::new_curated(merged, dialect);
    group.add("WordyPhrases", WordyPhrasesStubLinter::new());
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
    fn stub_fires_flag_me() {
        let checker = HarperChecker::new("US".into(), vec![]);
        let out = checker.check("FLAG_ME".into());
        assert_eq!(out.len(), 1, "stub must emit exactly one suggestion");
        let s = &out[0];
        assert!(matches!(s.category, SuggestionCategory::Clarity), "category must be Clarity");
        assert!(matches!(s.severity, Some(Severity::Medium)), "severity must be Some(Medium)");
        assert_eq!(s.priority, 220, "priority must be PRIORITY_MEDIUM (220)");
        assert_eq!(s.primary_replacement.as_deref(), Some("FLAGGED"), "replacement must be FLAGGED");
    }

    #[test]
    fn clarity_linter_survives_dict_add_cycle() {
        let checker = HarperChecker::new("US".into(), vec![]);
        assert_eq!(checker.check("FLAG_ME".into()).len(), 1, "stub fires pre-dict-add");
        let _ = checker.add_to_dictionary("somenewword".into());
        assert_eq!(checker.check("FLAG_ME".into()).len(), 1, "stub STILL fires post-dict-add");
    }
}
