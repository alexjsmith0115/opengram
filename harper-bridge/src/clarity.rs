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

#[cfg(test)]
mod tests {
    use super::*;

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
