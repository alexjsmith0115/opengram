import SwiftUI
import AppKit

/// About tab — app name, version, MIT license attribution for retext-simplify.
/// License text is loaded from the bundled THIRD_PARTY.txt resource at app-bundle level
/// (Bundle.main). The init accepts an explicit licenseText so unit tests can inject a
/// known string without relying on Bundle.main (test bundle does not host the resource).
struct AboutSettingsView: View {

    /// Drift guard: this string must match INFOPLIST_KEY_NSHumanReadableCopyright in
    /// OpenGram.xcodeproj/project.pbxproj (Debug + Release configs).
    static let defaultCopyrightString = "Copyright © 2026 OpenGram. Bundles retext-simplify dataset (MIT, © 2016 Titus Wormer)."

    static let licenseUnavailableFallback = "License text unavailable."

    let licenseText: String

    init(licenseText: String? = nil) {
        self.licenseText = licenseText ?? Self.loadLicense()
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OpenGram")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 4)
            Text("Version \(versionString)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer().frame(height: 24)

            Text("Acknowledgements")
                .font(.system(size: 13, weight: .semibold))
            Spacer().frame(height: 8)

            Text("OpenGram bundles the MIT-licensed retext-simplify wordy-phrase dataset. Full license text below.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer().frame(height: 8)

            ScrollView {
                Text(licenseText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 280)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            Spacer()
        }
        .padding(16)
        .frame(width: 400)
    }

    static func loadLicense() -> String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return licenseUnavailableFallback
        }
        return text
    }
}
