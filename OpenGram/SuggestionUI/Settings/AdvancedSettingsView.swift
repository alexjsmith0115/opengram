import SwiftUI
import Foundation

/// Advanced tab — exposes incremental check tunables. Warning text per D-09. All bindings
/// are @AppStorage to the same UserDefaults keys read by OpenGramConfig
/// (single source of truth — D-10). Reset button reuses the static defaults on
/// OpenGramConfig so the default values live in one place.
struct AdvancedSettingsView: View {

    static let warningText = "Advanced settings are unstable \u{2014} values may change between versions."

    // Key constants re-exported from OpenGramConfig (single source of truth).
    // The @AppStorage literals below MUST match these — enforced by
    // `appStorageKeys_matchConfigKeys` test.
    static let minIssueCountKey = OpenGramConfig.minIssueCountKey
    static let minWordCountKey = OpenGramConfig.minWordCountKey
    static let idleDebounceSecondsKey = OpenGramConfig.idleDebounceSecondsKey

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
                    minIssueCount = OpenGramConfig.defaultMinIssueCount
                    minWordCount = OpenGramConfig.defaultMinWordCount
                    idleDebounceSeconds = OpenGramConfig.defaultIdleDebounceSeconds
                    Self.resetDefaults(in: .standard)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    /// Test seam + single source of truth for the reset action. Writes the three
    /// OpenGramConfig.default* values into the provided suite and posts the change
    /// notification so eager-rescheduling consumers can flush caches.
    static func resetDefaults(in defaults: UserDefaults,
                              center: NotificationCenter = .default) {
        defaults.set(OpenGramConfig.defaultMinIssueCount, forKey: minIssueCountKey)
        defaults.set(OpenGramConfig.defaultMinWordCount, forKey: minWordCountKey)
        defaults.set(OpenGramConfig.defaultIdleDebounceSeconds, forKey: idleDebounceSecondsKey)
        OpenGramConfig.postDidChange(to: center)
    }
}
