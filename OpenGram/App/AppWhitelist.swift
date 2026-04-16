import Foundation

/// Bundle ID whitelist controlling which apps OpenGram will check.
///
/// Persists the user-customized set to UserDefaults as a newline-separated string.
/// When the stored value is empty (fresh install or after reset), the default set is used.
struct AppWhitelist {
    static let defaultBundleIDs: Set<String> = [
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.Mail",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers",
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",           // Arc
        "com.microsoft.Word",
        "com.microsoft.Outlook",
        "com.microsoft.Powerpoint",
        "com.microsoft.onenote.mac",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "ru.keepcoder.Telegram",
        "us.zoom.xos",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.jetbrains.intellij",
        "abnerworks.Typora",
        "notion.id",
        "md.obsidian",
    ]

    private let defaults: UserDefaults
    private static let storageKey = "whitelistedBundleIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var bundleIDs: Set<String> {
        guard let stored = defaults.array(forKey: Self.storageKey) as? [String], !stored.isEmpty else {
            return Self.defaultBundleIDs
        }
        return Set(stored)
    }

    func isAllowed(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }

    mutating func add(_ bundleID: String) {
        var current = bundleIDs
        current.insert(bundleID)
        persist(current)
    }

    mutating func remove(_ bundleID: String) {
        var current = bundleIDs
        current.remove(bundleID)
        persist(current)
    }

    /// Clears the stored value, reverting to the default set.
    mutating func resetToDefaults() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: Self.storageKey)
    }
}
