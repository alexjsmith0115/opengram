import Foundation
@preconcurrency import ApplicationServices

/// How the rewritten text should be written back to the source AX element.
/// Chosen at capture time based on the element's capability bits and the
/// presence (or absence) of a selection range. The same enum value drives
/// both the freshness-check read path and the destructive write path.
enum WriteBackStrategy: Sendable, Equatable {
    case rangeAndSelectedText(CFRange)
    case valueSplice(CFRange)
    case selectedTextOnly

    static func == (lhs: WriteBackStrategy, rhs: WriteBackStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.rangeAndSelectedText(let l), .rangeAndSelectedText(let r)):
            return l.location == r.location && l.length == r.length
        case (.valueSplice(let l), .valueSplice(let r)):
            return l.location == r.location && l.length == r.length
        case (.selectedTextOnly, .selectedTextOnly):
            return true
        default:
            return false
        }
    }

    /// Pick a strategy from the captured range and capability bits.
    /// Returns nil if no path is supported.
    static func choose(range: CFRange?, caps: AXCapabilities) -> WriteBackStrategy? {
        if let range = range {
            if caps.canSetSelectedTextRange && caps.canSetSelectedText {
                return .rangeAndSelectedText(range)
            }
            if caps.canReadValue && caps.canSetValue {
                return .valueSplice(range)
            }
            return nil
        } else {
            if caps.canSetSelectedText && caps.canReadSelectedText {
                return .selectedTextOnly
            }
            return nil
        }
    }
}
