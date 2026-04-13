@preconcurrency import ApplicationServices
import AppKit

/// Coordinates the overlay window: owns the OverlayWindow, converts Suggestion ranges
/// to screen positions via AX bounds queries, and manages the UnderlineView lifecycle.
///
/// Plans 02 and 03 add: popover, keyboard navigation, accept/dismiss, and write-back.
@MainActor
final class OverlayController {

    // T-03-02: cap displayed suggestions to prevent blocking the main thread with AX queries
    private static let maxDisplayedSuggestions = 50

    private let accessor: any AXAccessor
    private let overlayWindow: OverlayWindow
    private(set) var suggestions: [Suggestion] = []
    private var textContext: TextContext?
    private var underlineView: UnderlineView?

    init(accessor: any AXAccessor = SystemAXAccessor()) {
        self.accessor = accessor
        self.overlayWindow = OverlayWindow()
    }

    // MARK: - Bounds queries

    /// Converts a Suggestion's range to a CGRect in CG screen coordinates by querying
    /// the AX element for the glyph bounds. Returns nil on AX error or unpackable value.
    func boundsForRange(
        _ suggestion: Suggestion,
        in text: String,
        element: AXUIElement
    ) -> CGRect? {
        let cfRange = cfRangeFor(suggestion, in: text)
        var mutableRange = cfRange
        guard let axRangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        let (error, ref) = accessor.copyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute,
            axRangeValue
        )
        guard error == .success, let ref else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Converts CG screen coordinates (y=0 at bottom) to AppKit window coordinates (y=0 at top).
    func flipCGRect(_ cgRect: CGRect, screenHeight: CGFloat) -> NSRect {
        NSRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    // MARK: - Display lifecycle

    /// Positions the overlay window and renders underlines for all suggestions.
    /// Silently skips suggestions whose AX bounds query returns nil (per UI-SPEC error state).
    /// Capped at maxDisplayedSuggestions to avoid blocking the main thread (T-03-02).
    func show(suggestions: [Suggestion], context: TextContext) {
        self.suggestions = Array(suggestions.prefix(Self.maxDisplayedSuggestions))
        self.textContext = context

        let screenHeight = NSScreen.main?.frame.height ?? 0
        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for suggestion in self.suggestions {
            guard let cgRect = boundsForRange(suggestion, in: context.text, element: element) else {
                continue
            }
            let appKitRect = flipCGRect(cgRect, screenHeight: screenHeight)
            let underlineRect = NSRect(
                x: appKitRect.origin.x,
                y: appKitRect.origin.y,
                width: appKitRect.width,
                height: 2
            )
            let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
            entries.append(UnderlineEntry(
                underlineRect: underlineRect,
                hitRect: hitRect,
                suggestion: suggestion
            ))
        }

        guard !entries.isEmpty else { return }

        let unionRect = entries.reduce(CGRect.null) { $0.union($1.hitRect) }
        let padding: CGFloat = 4
        let windowRect = unionRect.insetBy(dx: -padding, dy: -padding)

        let view = UnderlineView()
        // Translate entry rects to window-local coordinates
        let localEntries = entries.map { entry in
            UnderlineEntry(
                underlineRect: entry.underlineRect.offsetBy(
                    dx: -windowRect.origin.x,
                    dy: -windowRect.origin.y
                ),
                hitRect: entry.hitRect.offsetBy(
                    dx: -windowRect.origin.x,
                    dy: -windowRect.origin.y
                ),
                suggestion: entry.suggestion
            )
        }
        view.entries = localEntries
        view.frame = NSRect(origin: .zero, size: windowRect.size)

        underlineView = view
        overlayWindow.contentView = view
        overlayWindow.setFrame(windowRect, display: false)
        overlayWindow.orderFront(nil)
    }

    /// Dismisses the overlay and resets all state.
    func dismiss() {
        overlayWindow.orderOut(nil)
        overlayWindow.contentView = nil
        underlineView = nil
        suggestions = []
        textContext = nil
    }

    // MARK: - Private helpers

    private func cfRangeFor(_ suggestion: Suggestion, in text: String) -> CFRange {
        let scalars = text.unicodeScalars
        let location = scalars.distance(from: scalars.startIndex, to: suggestion.range.lowerBound)
        let length = scalars.distance(from: suggestion.range.lowerBound, to: suggestion.range.upperBound)
        return CFRange(location: location, length: length)
    }
}
