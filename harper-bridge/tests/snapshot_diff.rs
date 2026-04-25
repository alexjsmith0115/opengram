//! Golden-snapshot regression test — 5 locked clarity entries.
//! Mismatch = CI fails; update tests/golden_clarity_snapshot.txt manually + commit.

use harper_bridge::{HarperChecker, SuggestionCategory};

const GOLDEN_PATH: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/golden_clarity_snapshot.txt");

const LOCKED_SENTENCES: &[&str] = &[
    "Please utilize this document.",
    "We should in order to finish early.",
    "At the present time, we need it.",
    "We need a number of solutions.",
    "We need additional resources.",
];

fn build_snapshot() -> String {
    let checker = HarperChecker::new("US".into(), vec![]);
    let mut lines: Vec<String> = Vec::new();
    for sentence in LOCKED_SENTENCES {
        let lints = checker.check((*sentence).into());
        for s in &lints {
            if matches!(s.category, SuggestionCategory::Clarity) {
                lines.push(format!(
                    "{}|{}|{}",
                    sentence,
                    s.primary_replacement.as_deref().unwrap_or(""),
                    s.priority,
                ));
            }
        }
    }
    lines.sort();
    let mut out = lines.join("\n");
    out.push('\n');
    out
}

#[test]
fn golden_snapshot_five_entries() {
    let raw = std::fs::read_to_string(GOLDEN_PATH)
        .unwrap_or_else(|e| panic!(
            "golden snapshot file missing at {} ({}). Run with --nocapture and copy the build_snapshot output below into the file:\n{}",
            GOLDEN_PATH, e, build_snapshot(),
        ));
    // Strip comment lines (lines starting with '#') — header is for humans only.
    let snapshot: String = raw
        .lines()
        .filter(|l| !l.starts_with('#'))
        .map(|l| format!("{}\n", l))
        .collect();
    let actual = build_snapshot();
    assert_eq!(
        snapshot, actual,
        "Snapshot mismatch — if intentional (dataset edit), update {} manually and commit.\n--- expected (golden) ---\n{}\n--- actual ---\n{}",
        GOLDEN_PATH, snapshot, actual,
    );
}

/// Diagnostic test — never asserts; prints actual snapshot output for debugging.
#[test]
#[ignore] // Run only on demand: cargo test --test snapshot_diff -- --ignored print_snapshot
fn print_snapshot() {
    eprintln!("{}", build_snapshot());
}
