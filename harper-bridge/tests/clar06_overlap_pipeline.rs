//! CLAR-06 production-pipeline integration test.
//!
//! Asserts `HarperChecker::check` applies `remove_overlaps` so the contract
//! "lower-priority-number wins on overlap" is enforced through the public FFI
//! surface — not just on synthetic Vec<Lint> in unit-test isolation.
//!
//! Input strategy: corpus contains two phrases where the longer is a superset
//! of the shorter:
//!   - "adversely impact"     → severity=medium → priority 220
//!   - "adversely impact on"  → severity=high   → priority 200
//!
//! Both fire on input "We will adversely impact on operations."
//!
//! Without `remove_overlaps`: 2 lints emitted.
//! With    `remove_overlaps`: 1 lint survives — priority 200 (lower number wins).

use harper_bridge::{HarperChecker, GrammarSuggestion, SuggestionCategory};

fn clarity_lints_for(text: &str) -> Vec<GrammarSuggestion> {
    let checker = HarperChecker::new("US".into(), vec![]);
    checker
        .check(text.into())
        .into_iter()
        .filter(|s| matches!(s.category, SuggestionCategory::Clarity))
        .collect()
}

#[test]
fn overlap_resolved_in_production_pipeline_clar06() {
    // Both "adversely impact" (medium=220) and "adversely impact on" (high=200)
    // span-overlap at byte offset 8. After remove_overlaps, exactly one survives
    // — the lower-priority-number one (longer phrase, "adversely impact on").
    let lints = clarity_lints_for("We will adversely impact on operations.");

    assert_eq!(
        lints.len(),
        1,
        "remove_overlaps must collapse overlapping clarity lints to exactly one (got {} = {:?})",
        lints.len(),
        lints.iter().map(|l| (&l.message, l.priority, l.start_char, l.end_char)).collect::<Vec<_>>()
    );

    let surviving = &lints[0];
    assert_eq!(
        surviving.priority, 200,
        "longer phrase (priority 200) must win over shorter (priority 220) per CLAR-06"
    );
    assert_eq!(
        surviving.primary_replacement.as_deref(),
        Some("hurt"),
        "surviving lint must be 'adversely impact on' → 'hurt'"
    );
}

#[test]
fn non_overlapping_clarity_lints_both_survive_clar06() {
    // Sanity: when phrases do NOT overlap, remove_overlaps must keep all of them.
    // "utilize" at offset 4-11; "in order to" elsewhere. Both must survive.
    let lints = clarity_lints_for("Will utilize this tool in order to finish.");
    let utilize_count = lints
        .iter()
        .filter(|s| s.primary_replacement.as_deref() == Some("use"))
        .count();
    let in_order_to_count = lints
        .iter()
        .filter(|s| s.primary_replacement.as_deref() == Some("to"))
        .count();
    assert_eq!(utilize_count, 1, "non-overlapping 'utilize' must still fire");
    assert_eq!(
        in_order_to_count, 1,
        "non-overlapping 'in order to' must still fire"
    );
}
