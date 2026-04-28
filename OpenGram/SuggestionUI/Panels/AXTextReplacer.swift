@preconcurrency import ApplicationServices
import Foundation
import os.log

@MainActor
final class AXTextReplacer {
    private let accessor: any AXAccessor
    private static let logger = Log.logger(for: "AXTextReplacer")

    init(accessor: any AXAccessor) { self.accessor = accessor }

    @discardableResult
    func replace(strategy: WriteBackStrategy,
                 replacement: String,
                 element: AXUIElement) -> Bool {
        switch strategy {
        case .rangeAndSelectedText(let range):
            return setRangeThenSelectedText(range, replacement: replacement, on: element)
        case .valueSplice(let range):
            return spliceFullValue(range, replacement: replacement, on: element)
        case .selectedTextOnly:
            return setSelectedText(replacement, on: element)
        }
    }

    private func setRangeThenSelectedText(_ range: CFRange, replacement: String, on element: AXUIElement) -> Bool {
        var rangeValue = range
        guard let axRange = AXValueCreate(.cfRange, &rangeValue) else { return false }
        let rangeErr = accessor.setAttributeValue(element, kAXSelectedTextRangeAttribute, axRange)
        guard rangeErr == .success else {
            Self.logger.error("set selected range failed: \(String(describing: rangeErr), privacy: .public)")
            return false
        }
        return setSelectedText(replacement, on: element)
    }

    private func spliceFullValue(_ range: CFRange, replacement: String, on element: AXUIElement) -> Bool {
        let (readErr, ref) = accessor.copyAttributeValue(element, kAXValueAttribute)
        guard readErr == .success, let current = ref as? String else { return false }
        guard let updated = AXRangeIndex.replacing(in: current, at: range, with: replacement) else { return false }
        let writeErr = accessor.setAttributeValue(element, kAXValueAttribute, updated as CFString)
        return writeErr == .success
    }

    private func setSelectedText(_ replacement: String, on element: AXUIElement) -> Bool {
        let err = accessor.setAttributeValue(element, kAXSelectedTextAttribute, replacement as CFString)
        return err == .success
    }
}
