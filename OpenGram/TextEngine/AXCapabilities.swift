import Foundation

/// Independent capability bits read from the focused AX element. Used to choose a
/// safe writeback strategy and to guard the freshness-check read path.
struct AXCapabilities: Sendable, Equatable {
    var canSetSelectedTextRange: Bool
    var canSetSelectedText: Bool
    var canReadSelectedText: Bool
    var canSetValue: Bool
    var canReadValue: Bool

    init(
        canSetSelectedTextRange: Bool = false,
        canSetSelectedText: Bool = false,
        canReadSelectedText: Bool = false,
        canSetValue: Bool = false,
        canReadValue: Bool = false
    ) {
        self.canSetSelectedTextRange = canSetSelectedTextRange
        self.canSetSelectedText = canSetSelectedText
        self.canReadSelectedText = canReadSelectedText
        self.canSetValue = canSetValue
        self.canReadValue = canReadValue
    }
}
