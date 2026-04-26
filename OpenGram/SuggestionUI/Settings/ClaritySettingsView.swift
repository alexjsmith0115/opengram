import SwiftUI
import Foundation

/// Clarity tab — master toggle for WordyPhrases rule + sub-toggle gating Low-severity entries.
/// Master toggle posts `.clarityMasterDidChange` consumed by AppDelegate, which dispatches
/// `setRuleEnabled("WordyPhrases", _)` on the retained HarperService — propagates without restart.
struct ClaritySettingsView: View {

    // Drift-guard constants. The @AppStorage literals below MUST match these
    // (property wrapper arguments must be compile-time constants).
    // Forwarded from `ClarityKeys` -- single source of truth shared with
    // HarperService and AppDelegate.
    static let clarityEnabledKey = ClarityKeys.clarityEnabledKey
    static let clarityOpinionatedEnabledKey = ClarityKeys.clarityOpinionatedEnabledKey
    static let defaultClarityEnabled: Bool = ClarityKeys.defaultClarityEnabled
    static let defaultClarityOpinionatedEnabled: Bool = ClarityKeys.defaultClarityOpinionatedEnabled

    @AppStorage("clarityEnabled") private var clarityEnabled: Bool = true
    @AppStorage("clarityOpinionatedEnabled") private var clarityOpinionatedEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Clarity Suggestions")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)

            Toggle("Enable Clarity Suggestions", isOn: $clarityEnabled)
                .font(.system(size: 13))
                .onChange(of: clarityEnabled) { _ in
                    Self.notifyMasterChanged()
                }
            Spacer().frame(height: 4)
            Text("Flags wordy phrases and suggests concise alternatives in real time.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer().frame(height: 24)

            Text("Options")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)

            Toggle("Show subjective clarity suggestions", isOn: $clarityOpinionatedEnabled)
                .font(.system(size: 13))
                .disabled(!clarityEnabled)
            Spacer().frame(height: 4)
            Text("Adds judgment-call replacements (e.g., minor wordiness) — off by default to avoid noise.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .opacity(clarityEnabled ? 1.0 : 0.4)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    /// Test seam — posts the master-changed notification on an injectable center.
    static func notifyMasterChanged(center: NotificationCenter = .default) {
        center.post(name: .clarityMasterDidChange, object: nil)
    }

    /// Test seam — mirrors the `.disabled(!clarityEnabled)` modifier applied to the
    /// sub-toggle in `body`. Pure function so tests can assert the invariant
    /// (sub-toggle disabled when master OFF) without ViewInspector.
    static func isSubToggleDisabled(masterOn: Bool) -> Bool {
        return !masterOn
    }
}
