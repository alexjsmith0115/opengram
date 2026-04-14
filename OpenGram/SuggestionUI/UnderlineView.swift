import AppKit

/// Data model for a single underline rendered by UnderlineView.
struct UnderlineEntry {
    let underlineRect: NSRect
    let hitRect: NSRect
    let suggestion: Suggestion
}

/// NSView subclass that renders colored underlines over flagged text ranges.
/// Overrides hitTest to pass non-underline clicks through to the target app.
@MainActor
final class UnderlineView: NSView {

    var entries: [UnderlineEntry] = []
    var onClick: ((Suggestion) -> Void)?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        for entry in entries {
            let path = NSBezierPath()
            path.lineWidth = 2.0
            path.move(to: NSPoint(x: entry.underlineRect.minX, y: entry.underlineRect.midY))
            path.line(to: NSPoint(x: entry.underlineRect.maxX, y: entry.underlineRect.midY))

            if Self.isDashedForSource(entry.suggestion.source) {
                let pattern: [CGFloat] = [4, 2]
                path.setLineDash(pattern, count: 2, phase: 0)
            }

            Self.colorForCategory(entry.suggestion.category).setStroke()
            path.stroke()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview?.convert(point, to: self) ?? point
        for entry in entries where entry.hitRect.contains(localPoint) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if let suggestion = suggestionAt(point: localPoint) {
            onClick?(suggestion)
        } else {
            super.mouseDown(with: event)
        }
    }

    func suggestionAt(point: NSPoint) -> Suggestion? {
        entries.first(where: { $0.hitRect.contains(point) })?.suggestion
    }

    override func resetCursorRects() {
        for entry in entries {
            addCursorRect(entry.hitRect, cursor: .pointingHand)
        }
    }

    // MARK: - Static helpers (nonisolated for testability without MainActor context)

    nonisolated static func colorForCategory(_ category: CheckCategory) -> NSColor {
        switch category {
        case .spelling: return .systemRed
        case .grammarPunctuation: return .systemBlue
        }
    }

    nonisolated static func isDashedForSource(_ source: SuggestionSource) -> Bool {
        switch source {
        case .harper: return false
        case .llm: return true
        }
    }

    /// Expands an underline rect by 6pt above and below to create a larger click target.
    nonisolated static func expandedHitRect(from underlineRect: NSRect) -> NSRect {
        NSRect(
            x: underlineRect.minX,
            y: underlineRect.minY - 6,
            width: underlineRect.width,
            height: underlineRect.height + 12
        )
    }
}
