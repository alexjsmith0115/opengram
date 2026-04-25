//! Non-blocking perf prints for CLAR-N1/N2/N4. Values logged via eprintln;
//! no asserts on thresholds (per REQUIREMENTS.md — perf is target, not gate).
//! Run with: cargo test --test perf_measurements -- --nocapture

use harper_bridge::HarperChecker;
use harper_bridge::clarity::get_corpus;
use std::time::Instant;

fn generate_500_word_doc() -> String {
    let seed = "We should utilize additional resources in order to accelerate the process. \
                At the present time, a number of issues require additional attention. \
                The accompanying documents accomplish their objective and ameliorate concerns. \
                Accordingly, we accede to the request and acquiesce to the proposed timeline. ";
    let mut out = String::new();
    while out.split_whitespace().count() < 500 {
        out.push_str(seed);
    }
    out
}

#[test]
fn perf_clar_n1_check_latency_500_words() {
    let text = generate_500_word_doc();
    let word_count = text.split_whitespace().count();
    let checker = HarperChecker::new("US".into(), vec![]);

    // Warm-up — first call triggers TOML parse + LintGroup construction.
    let _ = checker.check(text.clone());

    let iterations = 10u32;
    let copies: Vec<String> = (0..iterations).map(|_| text.clone()).collect();
    let start = Instant::now();
    for t in copies {
        let _ = checker.check(t);
    }
    let elapsed = start.elapsed();
    let avg_ms = elapsed.as_secs_f64() * 1000.0 / (iterations as f64);

    eprintln!(
        "CLAR-N1: avg check() on {}-word doc = {:.2}ms over {} iterations (target <=5ms, non-blocking)",
        word_count, avg_ms, iterations,
    );
    // No assert — value is logged, not gated.
}

#[test]
fn perf_clar_n2_bundle_size_delta() {
    let bytes = include_bytes!("../data/wordy_phrases.toml").len();
    let kb = bytes as f64 / 1024.0;
    eprintln!(
        "CLAR-N2: wordy_phrases.toml = {} bytes ({:.1}KB) (target <=200KB, non-blocking)",
        bytes, kb,
    );
    // No assert — value is logged, not gated.
}

#[test]
fn perf_clar_n4_unicode_scalar_check() {
    let corpus = get_corpus();
    let mut max_char = 0usize;
    let mut max_byte = 0usize;
    let mut multi_byte_entries = 0usize;
    for entry in corpus {
        let char_len = entry.phrase.chars().count();
        let byte_len = entry.phrase.len();
        if char_len != byte_len {
            multi_byte_entries += 1;
            eprintln!(
                "CLAR-N4: multi-byte phrase '{}' char={} byte={}",
                entry.phrase, char_len, byte_len
            );
        }
        max_char = max_char.max(char_len);
        max_byte = max_byte.max(byte_len);
    }
    eprintln!(
        "CLAR-N4: corpus_size={} max_chars={} max_bytes={} multi_byte_entries={} (NFC-normalized at dataset build time)",
        corpus.len(), max_char, max_byte, multi_byte_entries,
    );
    // No assert — value is logged, not gated.
}
