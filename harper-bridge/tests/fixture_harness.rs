//! Fixture harness — runtime iteration over get_corpus().
//! Per CLAR-20: positive fixtures (lowercase + sentence-start) and negative
//! fixtures (mid-word) per ParsedPhraseEntry; meta-tests guard the generator helpers.
//!
//! Aggregate failure reporting: all failures collected into Vec<String>;
//! one assert at the end reports every broken entry in a single run.
//!
//! Skip policy (per RESEARCH §Risks #1):
//! - Phrases containing '/', '\', '(', ')' or other non-letter punctuation:
//!   skip BOTH positive and negative fixtures; logged via eprintln.
//! - Multi-word phrases: positive fixtures still cover them; negative fixtures
//!   skip (cannot embed a multi-word phrase mid-word).

use harper_bridge::clarity::{get_corpus, ParsedPhraseEntry, Severity, WordyPhrasesLinter};
use harper_core::linting::{Lint, Linter, Suggestion};
use harper_core::parsers::PlainEnglish;
use harper_core::spell::{FstDictionary, MergedDictionary};
use harper_core::Document;
use std::sync::Arc;

fn make_merged_dict() -> Arc<MergedDictionary> {
    let mut merged = MergedDictionary::new();
    merged.add_dictionary(FstDictionary::curated());
    Arc::new(merged)
}

fn primary_replacement(lint: &Lint) -> Option<String> {
    lint.suggestions.first().and_then(|s| match s {
        Suggestion::ReplaceWith(chars) => Some(chars.iter().collect()),
        _ => None,
    })
}

fn sentence_start(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// Phrase contains only letters, spaces, hyphens, apostrophes — safe for fixture sentences.
/// Non-simple phrases (slash, backslash, parens, etc.) are skipped per RESEARCH §Risks #1.
fn is_simple_phrase(p: &str) -> bool {
    !p.is_empty()
        && p.chars()
            .all(|c| c.is_alphabetic() || c == ' ' || c == '-' || c == '\'')
}

/// Generator helper — extracted so meta-tests can verify in isolation.
fn run_positive_check(entry: &ParsedPhraseEntry, text: &str) -> bool {
    let merged = make_merged_dict();
    let mut linter = WordyPhrasesLinter::new_from_parsed(std::slice::from_ref(entry));
    let doc = Document::new(text, &PlainEnglish, merged.as_ref());
    linter.lint(&doc).iter().any(|l| {
        primary_replacement(l)
            .map(|r| r.eq_ignore_ascii_case(&entry.replacement))
            .unwrap_or(false)
    })
}

// ---------- META TESTS ----------

#[test]
fn meta_test_generator_detects_known_entry() {
    let synthetic = ParsedPhraseEntry {
        phrase: "utilize".to_string(),
        replacement: "use".to_string(),
        severity: Severity::High,
        dialects: None,
    };
    assert!(
        run_positive_check(&synthetic, "Please utilize now."),
        "meta: generator must detect 'utilize' in 'Please utilize now.'"
    );
}

#[test]
fn meta_test_generator_rejects_replacement_text() {
    let synthetic = ParsedPhraseEntry {
        phrase: "utilize".to_string(),
        replacement: "use".to_string(),
        severity: Severity::High,
        dialects: None,
    };
    assert!(
        !run_positive_check(&synthetic, "Please use now."),
        "meta: generator must not fire on replacement text 'use'"
    );
}

#[test]
fn meta_test_generator_rejects_unrelated_text() {
    let synthetic = ParsedPhraseEntry {
        phrase: "utilize".to_string(),
        replacement: "use".to_string(),
        severity: Severity::High,
        dialects: None,
    };
    assert!(
        !run_positive_check(&synthetic, "The cat sat on the mat."),
        "meta: generator must not fire on unrelated text"
    );
}

// ---------- POSITIVE FIXTURES ----------

#[test]
fn positive_fixtures_lowercase() {
    let corpus = get_corpus();
    let mut failures: Vec<String> = Vec::new();
    let mut skipped = 0usize;
    let mut tested = 0usize;

    for entry in corpus {
        if !is_simple_phrase(&entry.phrase) {
            eprintln!(
                "skip (non-simple): phrase='{}' replacement='{}'",
                entry.phrase, entry.replacement
            );
            skipped += 1;
            continue;
        }
        tested += 1;
        let input = format!("Please {} now.", entry.phrase);
        if !run_positive_check(entry, &input) {
            failures.push(format!(
                "lowercase: phrase='{}' replacement='{}' input='{}'",
                entry.phrase, entry.replacement, input,
            ));
        }
    }
    eprintln!(
        "positive_fixtures_lowercase: tested={} skipped={} failed={}",
        tested,
        skipped,
        failures.len()
    );
    assert!(
        failures.is_empty(),
        "positive lowercase fixtures FAILED ({}/{} tested):\n{}",
        failures.len(),
        tested,
        failures.join("\n")
    );
}

#[test]
fn positive_fixtures_sentence_start() {
    let corpus = get_corpus();
    let mut failures: Vec<String> = Vec::new();
    let mut skipped = 0usize;
    let mut tested = 0usize;

    for entry in corpus {
        if !is_simple_phrase(&entry.phrase) {
            skipped += 1;
            continue;
        }
        tested += 1;
        let cap = sentence_start(&entry.phrase);
        let input = format!("{} is important.", cap);
        if !run_positive_check(entry, &input) {
            failures.push(format!(
                "sentence-start: phrase='{}' replacement='{}' input='{}'",
                entry.phrase, entry.replacement, input,
            ));
        }
    }
    eprintln!(
        "positive_fixtures_sentence_start: tested={} skipped={} failed={}",
        tested,
        skipped,
        failures.len()
    );
    assert!(
        failures.is_empty(),
        "positive sentence-start fixtures FAILED ({}/{} tested):\n{}",
        failures.len(),
        tested,
        failures.join("\n")
    );
}

// ---------- NEGATIVE FIXTURES ----------

/// Single-word phrase = no whitespace + alphabetic only. Multi-word phrases
/// cannot be embedded mid-word so the negative-fixture strategy doesn't apply;
/// they're skipped here (positive fixtures still cover them).
fn is_single_word(p: &str) -> bool {
    !p.is_empty()
        && !p.contains(' ')
        && p.chars().all(|c| c.is_alphabetic() || c == '\'' || c == '-')
}

fn run_negative_check(entry: &ParsedPhraseEntry, text: &str) -> bool {
    let merged = make_merged_dict();
    let mut linter = WordyPhrasesLinter::new_from_parsed(std::slice::from_ref(entry));
    let doc = Document::new(text, &PlainEnglish, merged.as_ref());
    // Negative passes if NO lint emits a primary_replacement equal to entry.replacement
    !linter.lint(&doc).iter().any(|l| {
        primary_replacement(l)
            .map(|r| r.eq_ignore_ascii_case(&entry.replacement))
            .unwrap_or(false)
    })
}

#[test]
fn meta_test_negative_generator_rejects_midword() {
    let synthetic = ParsedPhraseEntry {
        phrase: "utilize".to_string(),
        replacement: "use".to_string(),
        severity: Severity::High,
        dialects: None,
    };
    // "unutilizeable" is one Word token; "utilize" appears mid-token only
    assert!(
        run_negative_check(&synthetic, "The unutilizeable thing arrived."),
        "meta: negative check must pass when phrase appears only mid-word"
    );
}

#[test]
fn negative_fixtures_midword() {
    let corpus = get_corpus();
    let mut failures: Vec<String> = Vec::new();
    let mut skipped = 0usize;
    let mut tested = 0usize;

    for entry in corpus {
        if !is_single_word(&entry.phrase) {
            skipped += 1;
            continue;
        }
        tested += 1;
        let input = format!("The un{}able thing arrived.", entry.phrase);
        if !run_negative_check(entry, &input) {
            failures.push(format!(
                "midword negative: phrase='{}' input='{}' (lint fired but should not)",
                entry.phrase, input,
            ));
        }
    }
    eprintln!(
        "negative_fixtures_midword: tested={} skipped={} failed={}",
        tested,
        skipped,
        failures.len()
    );
    assert!(
        failures.is_empty(),
        "negative midword fixtures FAILED ({}/{} tested):\n{}",
        failures.len(),
        tested,
        failures.join("\n")
    );
}
