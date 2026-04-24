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

use harper_core::Document;
use harper_core::TokenKind;
use harper_core::linting::{Lint, LintKind, Linter, Suggestion};
use harper_core::Punctuation;

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
}

#[cfg(test)]
mod spike {
    //! MapPhraseLinter wrapper spike test harness (plan 06 fills impl + assertions).
    //! 5-regime case preservation + priority-rewrite stability (D-03 hard gates).

    #[test]
    fn case_preservation_five_regimes() {
        // Filled by plan 06. Currently asserts false to stay RED.
        assert!(false, "spike impl pending — plan 06");
    }

    #[test]
    fn priority_rewrite_no_default_leak() {
        // Filled by plan 06. Currently asserts false to stay RED.
        assert!(false, "spike impl pending — plan 06");
    }
}
