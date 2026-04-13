@preconcurrency import ApplicationServices
import AppKit
import Foundation

final class AXTextEngine: AXTextEngineProtocol {
    private let accessor: any AXAccessor
    private let capabilityCache: any AXCapabilityCacheProtocol

    private static let maxTextLength = 100 * 1024 // T-01-09: 100KB limit on extracted text

    init(accessor: any AXAccessor, capabilityCache: any AXCapabilityCacheProtocol) {
        self.accessor = accessor
        self.capabilityCache = capabilityCache
    }

    convenience init(capabilityCache: any AXCapabilityCacheProtocol) {
        self.init(accessor: SystemAXAccessor(), capabilityCache: capabilityCache)
    }

    @MainActor func extractText() -> TextContext? {
        guard accessor.isProcessTrusted() else { return nil }

        guard let bundleID = accessor.frontmostBundleID() else { return nil }
        let version = accessor.frontmostBundleVersion()

        if let cached = capabilityCache.isSupported(bundleID: bundleID, version: version), !cached {
            return nil
        }

        let systemWide = accessor.systemWideElement()
        let (focusError, focusedRef) = accessor.copyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute
        )
        guard focusError == .success, let ref = focusedRef else { return nil }

        let element = ref as! AXUIElement

        if capabilityCache.isSupported(bundleID: bundleID, version: version) == nil {
            let supported = probeCapability(element: element)
            capabilityCache.store(bundleID: bundleID, version: version, supported: supported)
            if !supported { return nil }
        }

        let extractionMethod: ExtractionMethod
        let text: String

        let (selError, selRef) = accessor.copyAttributeValue(element, kAXSelectedTextAttribute)
        if selError == .success, let selStr = selRef as? String, !selStr.isEmpty {
            extractionMethod = .axDirectSelection
            text = selStr
        } else {
            let (valError, valRef) = accessor.copyAttributeValue(element, kAXValueAttribute)
            if valError == .success, let valStr = valRef as? String, !valStr.isEmpty {
                extractionMethod = .axDirectFull
                text = valStr
            } else {
                return nil
            }
        }

        let truncatedText = text.count > Self.maxTextLength
            ? String(text.prefix(Self.maxTextLength))
            : text

        let selectionRange = extractSelectionRange(element: element)
        let elementBounds = extractElementBounds(element: element)

        return TextContext(
            text: truncatedText,
            bundleID: bundleID,
            extractionMethod: extractionMethod,
            selectionRange: selectionRange,
            elementBounds: elementBounds,
            axElement: element
        )
    }

    @MainActor func probeCapability(element: AXUIElement) -> Bool {
        let (readError, _) = accessor.copyAttributeValue(element, kAXValueAttribute)
        guard readError == .success || readError == .noValue else { return false }

        let (settableError, settable) = accessor.isAttributeSettable(element, kAXValueAttribute)
        guard settableError == .success else { return false }
        return settable
    }

    @MainActor func writeBack(context: TextContext, replacement: String) -> Bool {
        // Re-validate element is still live (Pitfall 5)
        let (checkError, _) = accessor.copyAttributeValue(context.axElement, kAXValueAttribute)
        guard checkError == .success else { return false }

        // Re-establish selection if range is available
        if let range = context.selectionRange {
            var mutableRange = range
            if let axValue = AXValueCreate(.cfRange, &mutableRange) {
                _ = accessor.setAttributeValue(
                    context.axElement, kAXSelectedTextRangeAttribute, axValue
                )
            }
        }

        // Replace via kAXSelectedTextAttribute -- never kAXValueAttribute (Pitfall 6)
        let result = accessor.setAttributeValue(
            context.axElement, kAXSelectedTextAttribute, replacement as CFString
        )
        return result == .success
    }

    // MARK: - Private helpers

    private func extractSelectionRange(element: AXUIElement) -> CFRange? {
        let (error, ref) = accessor.copyAttributeValue(element, kAXSelectedTextRangeAttribute)
        guard error == .success, let axValue = ref else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func extractElementBounds(element: AXUIElement) -> CGRect? {
        let (posError, posRef) = accessor.copyAttributeValue(element, kAXPositionAttribute)
        guard posError == .success, let posValue = posRef else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }

        let (sizeError, sizeRef) = accessor.copyAttributeValue(element, kAXSizeAttribute)
        guard sizeError == .success, let sizeValue = sizeRef else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: point, size: size)
    }
}
