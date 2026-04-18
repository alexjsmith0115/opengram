import SwiftUI
import Foundation

/// Advanced tab — exposes incremental check tunables. Warning text per D-09. All bindings
/// are @AppStorage to the same UserDefaults keys read by UserDefaultsIncrementalConfig
/// (single source of truth — D-10). Reset button reuses the static defaults on
/// UserDefaultsIncrementalConfig so the default values live in one place.
struct AdvancedSettingsView: View {

    static let warningText = "Advanced settings are unstable \u{2014} values may change between versions."

    // Key constants re-exported from UserDefaultsIncrementalConfig (single source of truth).
    // The @AppStorage literals below MUST match these — enforced by
    // `appStorageKeys_matchConfigKeys` test.
    static let minIssueCountKey = UserDefaultsIncrementalConfig.minIssueCountKey
    static let minWordCountKey = UserDefaultsIncrementalConfig.minWordCountKey
    static let idleDebounceSecondsKey = UserDefaultsIncrementalConfig.idleDebounceSecondsKey

    @AppStorage("llmMinIssueCount") private var minIssueCount: Int = 2
    @AppStorage("llmMinWordCount") private var minWordCount: Int = 12
    @AppStorage("llmIdleDebounceSeconds") private var idleDebounceSeconds: Double = 1.5

    var body: some View {
        Form {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(Self.warningText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Divider()
            Stepper("Min issues per card: \(minIssueCount)",
                    value: $minIssueCount, in: 1...10)
            Stepper("Min words per paragraph: \(minWordCount)",
                    value: $minWordCount, in: 1...50)
            Stepper(value: $idleDebounceSeconds, in: 0.5...10.0, step: 0.5) {
                Text("Idle debounce: \(idleDebounceSeconds, specifier: "%.1f")s")
            }
            Divider()
            HStack {
                Spacer()
                Button("Reset to defaults") {
                    minIssueCount = UserDefaultsIncrementalConfig.defaultMinIssueCount
                    minWordCount = UserDefaultsIncrementalConfig.defaultMinWordCount
                    idleDebounceSeconds = UserDefaultsIncrementalConfig.defaultIdleDebounceSeconds
                    Self.resetDefaults(in: .standard)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    /// Test seam + single source of truth for the reset action. Writes the three
    /// UserDefaultsIncrementalConfig.default* values into the provided suite.
    static func resetDefaults(in defaults: UserDefaults) {
        defaults.set(UserDefaultsIncrementalConfig.defaultMinIssueCount, forKey: minIssueCountKey)
        defaults.set(UserDefaultsIncrementalConfig.defaultMinWordCount, forKey: minWordCountKey)
        defaults.set(UserDefaultsIncrementalConfig.defaultIdleDebounceSeconds, forKey: idleDebounceSecondsKey)
    }
}
