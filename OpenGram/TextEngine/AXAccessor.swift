@preconcurrency import ApplicationServices
import AppKit

/// Abstracts macOS Accessibility C API calls for testability via DI.
/// Production code uses SystemAXAccessor; tests inject MockAXAccessor.
protocol AXAccessor: Sendable {
    func copyAttributeValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, CFTypeRef?)

    func isAttributeSettable(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, Bool)

    func setAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ value: CFTypeRef
    ) -> AXError

    func copyParameterizedAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ parameter: CFTypeRef
    ) -> (AXError, CFTypeRef?)

    func isProcessTrusted() -> Bool
    func systemWideElement() -> AXUIElement

    func frontmostBundleID() -> String?
    func frontmostBundleVersion() -> String?
}

/// Wraps real macOS AX C API calls.
final class SystemAXAccessor: AXAccessor {
    func copyAttributeValue(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, CFTypeRef?) {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return (error, ref)
    }

    func isAttributeSettable(
        _ element: AXUIElement,
        _ attribute: String
    ) -> (AXError, Bool) {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return (error, settable.boolValue)
    }

    func setAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ value: CFTypeRef
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    func copyParameterizedAttributeValue(
        _ element: AXUIElement,
        _ attribute: String,
        _ parameter: CFTypeRef
    ) -> (AXError, CFTypeRef?) {
        var ref: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element, attribute as CFString, parameter, &ref
        )
        return (error, ref)
    }

    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func systemWideElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func frontmostBundleVersion() -> String? {
        guard let url = NSWorkspace.shared.frontmostApplication?.bundleURL else { return nil }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
