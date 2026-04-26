import Testing
import Foundation

@testable import OpenGramLib

@Suite("AppWhitelist")
struct AppWhitelistTests {

    private func makeSUT() -> (AppWhitelist, UserDefaults) {
        let suiteName = "app-whitelist-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let whitelist = AppWhitelist(defaults: defaults)
        return (whitelist, defaults)
    }

    @Test("Default whitelist includes key apps")
    func defaultsIncludeKeyApps() {
        let (whitelist, _) = makeSUT()
        #expect(whitelist.bundleIDs.contains("com.apple.TextEdit"))
        #expect(whitelist.bundleIDs.contains("com.apple.Notes"))
        #expect(whitelist.bundleIDs.contains("com.apple.Safari"))
        #expect(whitelist.bundleIDs.contains("com.google.Chrome"))
        #expect(whitelist.bundleIDs.contains("com.microsoft.Outlook"))
        #expect(whitelist.bundleIDs.contains("com.tinyspeck.slackmacgap"))
    }

    @Test("isAllowed returns true for whitelisted bundle ID")
    func isAllowedReturnsTrueForWhitelistedID() {
        let (whitelist, _) = makeSUT()
        #expect(whitelist.isAllowed("com.apple.Notes") == true)
    }

    @Test("isAllowed returns false for com.googlecode.iterm2")
    func isAllowedReturnsFalseForITerm2() {
        let (whitelist, _) = makeSUT()
        #expect(whitelist.isAllowed("com.googlecode.iterm2") == false)
    }

    @Test("add persists new bundle ID")
    func addPersistsNewBundleID() {
        var (whitelist, _) = makeSUT()
        whitelist.add("com.example.newapp")
        #expect(whitelist.isAllowed("com.example.newapp") == true)
    }

    @Test("remove persists removal")
    func removePersistsRemoval() {
        var (whitelist, _) = makeSUT()
        whitelist.add("com.example.toremove")
        whitelist.remove("com.example.toremove")
        #expect(whitelist.isAllowed("com.example.toremove") == false)
    }

    @Test("resetToDefaults restores default set")
    func resetToDefaultsRestoresDefaults() {
        var (whitelist, _) = makeSUT()
        whitelist.add("com.example.custom")
        whitelist.resetToDefaults()
        // Custom entry gone after reset
        #expect(whitelist.isAllowed("com.example.custom") == false)
        // Default entries are back
        #expect(whitelist.isAllowed("com.apple.Notes") == true)
    }
}
