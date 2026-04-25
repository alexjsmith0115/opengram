import Testing
import Foundation
@testable import OpenGramLib

@Suite @MainActor struct AboutSettingsViewTests {

    @Test func init_withExplicitLicenseText_storesIt() {
        let view = AboutSettingsView(licenseText: "synthetic license body")
        #expect(view.licenseText == "synthetic license body")
    }

    @Test func init_withFallbackText_storesFallback() {
        let view = AboutSettingsView(licenseText: AboutSettingsView.licenseUnavailableFallback)
        #expect(view.licenseText == "License text unavailable.")
    }

    @Test func licenseUnavailableFallback_isStable() {
        #expect(AboutSettingsView.licenseUnavailableFallback == "License text unavailable.")
    }

    @Test func defaultCopyrightString_matchesInfoPlistKey() {
        // Drift guard against pbxproj INFOPLIST_KEY_NSHumanReadableCopyright (Task 2).
        let expected = "Copyright © 2026 OpenGram. Bundles retext-simplify dataset (MIT, © 2016 Titus Wormer)."
        #expect(AboutSettingsView.defaultCopyrightString == expected)
    }
}
