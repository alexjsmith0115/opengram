//! NonFlags regression corpus — every line in `tests/nonflags/*.txt` MUST produce
//! zero `WordyPhrasesLinter` lints. Comments (`#`) and blank lines are ignored.
//! Per-category test fns aggregate failures into Vec<String> + single final assert,
//! mirroring `fixture_harness.rs` aggregate-failure pattern.
//!
//! CLAR-21.

use harper_bridge::clarity::{get_corpus, WordyPhrasesLinter};
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

/// Strip comments + blank lines. Returns (1-indexed line number, trimmed sentence).
fn parse_fixture_file(raw: &str) -> Vec<(usize, String)> {
    raw.lines()
        .enumerate()
        .filter_map(|(i, line)| {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                None
            } else {
                Some((i + 1, trimmed.to_string()))
            }
        })
        .collect()
}

/// Run zero-lint check across every fixture line. Returns failure messages.
/// Linter constructed ONCE per call to keep <5s perf budget across all 4 fns.
fn run_zero_lint_check(raw: &str, file_label: &str) -> Vec<String> {
    let lines = parse_fixture_file(raw);
    let merged = make_merged_dict();
    let mut linter = WordyPhrasesLinter::new_from_parsed(get_corpus());
    let mut failures: Vec<String> = Vec::new();

    for (line_no, sentence) in lines {
        let doc = Document::new(&sentence, &PlainEnglish, merged.as_ref());
        let lints = linter.lint(&doc);
        if !lints.is_empty() {
            let summaries: Vec<String> = lints
                .iter()
                .map(|l| {
                    primary_replacement(l)
                        .map(|r| format!("→{}", r))
                        .unwrap_or_else(|| "<no-replacement>".to_string())
                })
                .collect();
            failures.push(format!(
                "{} L{}: '{}' produced {} lint(s): {}",
                file_label,
                line_no,
                sentence,
                lints.len(),
                summaries.join(", ")
            ));
        }
    }
    failures
}

#[test]
fn nonflags_proper_nouns() {
    let failures = run_zero_lint_check(
        include_str!("nonflags/proper_nouns.txt"),
        "nonflags/proper_nouns.txt",
    );
    assert!(
        failures.is_empty(),
        "proper_nouns.txt — {} fixture(s) wrongly flagged:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn nonflags_quoted_code() {
    let failures = run_zero_lint_check(
        include_str!("nonflags/quoted_code.txt"),
        "nonflags/quoted_code.txt",
    );
    assert!(
        failures.is_empty(),
        "quoted_code.txt — {} fixture(s) wrongly flagged:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn nonflags_domain_terms() {
    let failures = run_zero_lint_check(
        include_str!("nonflags/domain_terms.txt"),
        "nonflags/domain_terms.txt",
    );
    assert!(
        failures.is_empty(),
        "domain_terms.txt — {} fixture(s) wrongly flagged:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn nonflags_retext_issues() {
    let failures = run_zero_lint_check(
        include_str!("nonflags/retext_issues.txt"),
        "nonflags/retext_issues.txt",
    );
    assert!(
        failures.is_empty(),
        "retext_issues.txt — {} fixture(s) wrongly flagged:\n{}",
        failures.len(),
        failures.join("\n")
    );
}

#[test]
fn nonflags_meta_corpus_size() {
    // Guard: total non-comment non-blank lines across all 4 fixture files ≥100.
    // Fail-fast on accidental fixture deletion. CLAR-21.
    let proper_nouns = parse_fixture_file(include_str!("nonflags/proper_nouns.txt")).len();
    let quoted_code = parse_fixture_file(include_str!("nonflags/quoted_code.txt")).len();
    let domain_terms = parse_fixture_file(include_str!("nonflags/domain_terms.txt")).len();
    let retext_issues = parse_fixture_file(include_str!("nonflags/retext_issues.txt")).len();
    let total = proper_nouns + quoted_code + domain_terms + retext_issues;

    assert!(
        total >= 100,
        "NonFlags corpus shrunk below threshold: total={} non-comment lines (expected ≥100). \
         Per-category counts: proper_nouns={}, quoted_code={}, domain_terms={}, retext_issues={}. \
         Did someone delete fixtures? Add lines back to harper-bridge/tests/nonflags/*.txt.",
        total, proper_nouns, quoted_code, domain_terms, retext_issues
    );
}
