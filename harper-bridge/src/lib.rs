use std::sync::{Arc, Mutex};

use harper_core::linting::{LintGroup, LintKind, Linter, Suggestion};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::{FstDictionary, MergedDictionary, MutableDictionary};
use harper_core::{Dialect, Document};

uniffi::setup_scaffolding!();

/// Two-bucket category mapping per D-03: spelling (red) and grammar+punctuation (blue).
#[derive(uniffi::Enum)]
pub enum SuggestionCategory {
    Spelling,
    GrammarPunctuation,
}

/// Carries all Harper replacements so Phase 3 can decide presentation (D-01).
/// Char offsets index into the Swift String.unicodeScalars view.
#[derive(uniffi::Record)]
pub struct GrammarSuggestion {
    pub start_char: u32,
    pub end_char: u32,
    pub message: String,
    pub primary_replacement: Option<String>,
    pub all_replacements: Vec<String>,
    pub category: SuggestionCategory,
    pub priority: u8,
}

/// UniFFI wraps objects in Arc, so interior mutability via Mutex is required
/// since LintGroup::lint and MutableDictionary both need &mut self.
#[derive(uniffi::Object)]
pub struct HarperChecker {
    inner: Mutex<HarperCheckerInner>,
}

struct HarperCheckerInner {
    linter: LintGroup,
    user_dict: MutableDictionary,
    user_words: Vec<String>,
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
        let base = FstDictionary::curated();
        let mut user_dict = MutableDictionary::new();
        user_dict.extend_words(user_words.iter().map(|w| {
            (w.chars().collect::<Vec<char>>(), Default::default())
        }));

        let mut merged = MergedDictionary::new();
        merged.add_dictionary(base);
        merged.add_dictionary(Arc::new(user_dict.clone()));

        let dialect = parse_dialect(&dialect_abbr);

        Self {
            inner: Mutex::new(HarperCheckerInner {
                linter: LintGroup::new_curated(Arc::new(merged), dialect),
                user_dict,
                user_words: user_words.clone(),
            }),
        }
    }

    pub fn check(&self, text: String) -> Vec<GrammarSuggestion> {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        let document = Document::new_curated(&text, &PlainEnglish);
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

                let category = match lint.lint_kind {
                    LintKind::Spelling => SuggestionCategory::Spelling,
                    _ => SuggestionCategory::GrammarPunctuation,
                };

                GrammarSuggestion {
                    start_char: span.start as u32,
                    end_char: span.end as u32,
                    message: lint.message,
                    primary_replacement,
                    all_replacements,
                    category,
                    priority: lint.priority,
                }
            })
            .collect()
    }

    /// Adds a word to the user dictionary and returns the full updated word list
    /// for Swift to persist to dictionary.txt (D-06).
    pub fn add_to_dictionary(&self, word: String) -> Vec<String> {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        inner.user_dict.append_word_str(&word, Default::default());
        inner.user_words.push(word);
        inner.user_words.clone()
    }

    /// Enable/disable a named rule. Keys match FlatConfig rule names (GRAM-09).
    pub fn set_rule_enabled(&self, rule_key: String, enabled: bool) {
        let mut inner = self.inner.lock().expect("HarperChecker lock poisoned");
        inner.linter.config.set_rule_enabled(&rule_key, enabled);
    }
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
