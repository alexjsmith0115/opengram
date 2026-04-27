@preconcurrency import ApplicationServices
import AppKit
import Foundation

final class AXTextEngine: AXTextEngineProtocol {
    private static let logger = Log.logger(for: "AXTextEngine")

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
        guard accessor.isProcessTrusted() else {
            Self.logger.warning("extractText aborted: AX process is not trusted")
            return nil
        }

        guard let bundleID = accessor.frontmostBundleID() else {
            Self.logger.warning("extractText aborted: no frontmost bundle ID")
            return nil
        }
        let version = accessor.frontmostBundleVersion()
        let cachedSupport = capabilityCache.isSupported(bundleID: bundleID, version: version)
        Self.logger.info("extractText start bundle=\(bundleID, privacy: .public) version=\(version ?? "nil", privacy: .public) cachedSupport=\(String(describing: cachedSupport), privacy: .public)")

        if let cached = cachedSupport,
           !cached,
           !Self.shouldReprobeCachedUnsupported(bundleID: bundleID) {
            Self.logger.info("extractText aborted: cached unsupported bundle=\(bundleID, privacy: .public) version=\(version ?? "nil", privacy: .public)")
            return nil
        }

        let systemWide = accessor.systemWideElement()
        let (focusError, focusedRef) = accessor.copyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute
        )
        guard focusError == .success, let ref = focusedRef else {
            Self.logger.warning("extractText aborted: focused element read failed err=\(focusError.rawValue)")
            return nil
        }

        let element = ref as! AXUIElement
        Self.logElementSummary(element, bundleID: bundleID)

        let shouldProbe = cachedSupport == nil
            || (cachedSupport == false && Self.shouldReprobeCachedUnsupported(bundleID: bundleID))
        if shouldProbe {
            let supported = probeCapability(element: element)
            capabilityCache.store(bundleID: bundleID, version: version, supported: supported)
            Self.logger.info("capability probe stored bundle=\(bundleID, privacy: .public) version=\(version ?? "nil", privacy: .public) supported=\(supported)")
            if !supported {
                Self.logger.info("extractText aborted: capability probe unsupported bundle=\(bundleID, privacy: .public)")
                return nil
            }
        }

        let extractionMethod: ExtractionMethod
        let text: String

        let (selError, selRef) = accessor.copyAttributeValue(element, kAXSelectedTextAttribute)
        if selError == .success, let selStr = selRef as? String, !selStr.isEmpty {
            extractionMethod = .axDirectSelection
            text = selStr
            Self.logger.info("extractText selected text len=\(selStr.count) sample=\(Self.sample(selStr), privacy: .public)")
        } else {
            Self.logger.info("extractText selected text unavailable err=\(selError.rawValue) cast=\(selRef is String) empty=\(((selRef as? String)?.isEmpty ?? false))")
            let (valError, valRef) = accessor.copyAttributeValue(element, kAXValueAttribute)
            if valError == .success, let valStr = valRef as? String, !valStr.isEmpty {
                extractionMethod = .axDirectFull
                text = valStr
                Self.logger.info("extractText full value len=\(valStr.count) sample=\(Self.sample(valStr), privacy: .public)")
            } else {
                Self.logger.warning("extractText aborted: no selected text or value valErr=\(valError.rawValue) valueCast=\(valRef is String) valueEmpty=\(((valRef as? String)?.isEmpty ?? false))")
                return nil
            }
        }

        let truncatedText = text.count > Self.maxTextLength
            ? String(text.prefix(Self.maxTextLength))
            : text

        let selectionRange = extractSelectionRange(element: element)
        let elementBounds = extractElementBounds(element: element)
        let capabilities = extractCapabilities(element: element)

        Self.logger.info("extractText success bundle=\(bundleID, privacy: .public) method=\(extractionMethod.rawValue, privacy: .public) textLen=\(truncatedText.count) selection=\(Self.describe(selectionRange), privacy: .public) bounds=\(Self.describe(elementBounds), privacy: .public)")

        return TextContext(
            text: truncatedText,
            bundleID: bundleID,
            extractionMethod: extractionMethod,
            selectionRange: selectionRange,
            elementBounds: elementBounds,
            capabilities: capabilities,
            axElement: element
        )
    }

    @MainActor func probeCapability(element: AXUIElement) -> Bool {
        let (readError, _) = accessor.copyAttributeValue(element, kAXValueAttribute)
        guard readError == .success || readError == .noValue else {
            Self.logger.info("probeCapability failed: value read err=\(readError.rawValue)")
            return false
        }

        let (valueSettableError, valueSettable) = accessor.isAttributeSettable(
            element, kAXValueAttribute
        )
        Self.logger.info("probeCapability value settable err=\(valueSettableError.rawValue) settable=\(valueSettable)")
        if valueSettableError == .success && valueSettable {
            return true
        }

        let (rangeSettableError, rangeSettable) = accessor.isAttributeSettable(
            element, kAXSelectedTextRangeAttribute
        )
        Self.logger.info("probeCapability selected range settable err=\(rangeSettableError.rawValue) settable=\(rangeSettable)")
        if rangeSettableError == .success && rangeSettable {
            return true
        }

        let (selectedTextSettableError, selectedTextSettable) = accessor.isAttributeSettable(
            element, kAXSelectedTextAttribute
        )
        Self.logger.info("probeCapability selected text settable err=\(selectedTextSettableError.rawValue) settable=\(selectedTextSettable)")
        return selectedTextSettableError == .success && selectedTextSettable
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

    private func extractCapabilities(element: AXUIElement) -> AXCapabilities {
        let (_, rangeSettable) = accessor.isAttributeSettable(element, kAXSelectedTextRangeAttribute)
        let (_, selectedTextSettable) = accessor.isAttributeSettable(element, kAXSelectedTextAttribute)
        let (_, valueSettable) = accessor.isAttributeSettable(element, kAXValueAttribute)

        let (selReadError, _) = accessor.copyAttributeValue(element, kAXSelectedTextAttribute)
        let (valReadError, _) = accessor.copyAttributeValue(element, kAXValueAttribute)

        return AXCapabilities(
            canSetSelectedTextRange: rangeSettable,
            canSetSelectedText: selectedTextSettable,
            canReadSelectedText: selReadError == .success || selReadError == .noValue,
            canSetValue: valueSettable,
            canReadValue: valReadError == .success || valReadError == .noValue
        )
    }

    private static func shouldReprobeCachedUnsupported(bundleID: String) -> Bool {
        bundleID == "com.microsoft.Outlook"
    }

    private static func logElementSummary(_ element: AXUIElement, bundleID: String) {
        let role = attributeString(element, kAXRoleAttribute) ?? "nil"
        let subrole = attributeString(element, kAXSubroleAttribute) ?? "nil"
        let title = attributeString(element, kAXTitleAttribute) ?? "nil"
        let description = attributeString(element, kAXDescriptionAttribute) ?? "nil"
        Self.logger.info("focused element bundle=\(bundleID, privacy: .public) role=\(role, privacy: .public) subrole=\(subrole, privacy: .public) title=\(title, privacy: .public) description=\(description, privacy: .public)")
    }

    private static func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == CFStringGetTypeID() else { return nil }
        return ref as? String
    }

    private static func sample(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return String(oneLine.prefix(160))
    }

    private static func describe(_ range: CFRange?) -> String {
        guard let range else { return "nil" }
        return "{location:\(range.location), length:\(range.length)}"
    }

    private static func describe(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return NSStringFromRect(rect)
    }
}
