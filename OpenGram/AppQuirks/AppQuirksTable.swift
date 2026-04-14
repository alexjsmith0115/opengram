import AppKit

/// Per-app AX behavior configuration loaded from the bundled AppQuirks.plist.
///
/// All fields are optional. A nil field means "use the default behavior."
struct AppQuirk: Codable {
    /// Horizontal pixel offset to apply to all AX-returned bounds for this app.
    var coordinateOffsetX: CGFloat?
    /// Vertical pixel offset to apply to all AX-returned bounds for this app.
    var coordinateOffsetY: CGFloat?
    /// Multiplier for estimated line height (affects multi-line detection threshold).
    var lineHeightFactor: CGFloat?
    /// Override for the bounds query strategy: "rangeBounds" (default) or "skipMultiLine".
    var boundsStrategy: String?
}

/// Loads per-app AX quirks from the bundled AppQuirks.plist and provides O(1) lookup.
final class AppQuirksTable: Sendable {

    static let shared = AppQuirksTable()

    private let quirks: [String: AppQuirk]

    init() {
        guard let url = Bundle.main.url(forResource: "AppQuirks", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let loaded = try? PropertyListDecoder().decode([String: AppQuirk].self, from: data) else {
            // Silent failure: no quirks applied. App functions correctly without quirks.
            print("[AppQuirksTable] Failed to load AppQuirks.plist — using empty table")
            self.quirks = [:]
            return
        }
        self.quirks = loaded
    }

    // Internal init for tests to inject pre-loaded quirks.
    init(quirks: [String: AppQuirk]) {
        self.quirks = quirks
    }

    /// Returns the quirk configuration for the given bundle ID, or nil if none is registered.
    func quirk(for bundleID: String) -> AppQuirk? {
        quirks[bundleID]
    }
}
