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

        // PLL-01b / PLL-13: draw LLM entries FIRST so Harper entries overlay on top.
        let sorted = entries.sorted { a, b in
            let aOrder = (a.suggestion.source == .llm) ? 0 : 1
            let bOrder = (b.suggestion.source == .llm) ? 0 : 1
            return aOrder < bOrder
        }

        for entry in sorted {
            let path = NSBezierPath()
            path.lineWidth = 2.0
            path.move(to: NSPoint(x: entry.underlineRect.minX, y: entry.underlineRect.midY))
            path.line(to: NSPoint(x: entry.underlineRect.maxX, y: entry.underlineRect.midY))

            if Self.isDashedForSource(entry.suggestion.source) {
                let pattern: [CGFloat] = [4, 2]
                path.setLineDash(pattern, count: 2, phase: 0)
            }

            Self.colorForSuggestion(entry.suggestion).setStroke()
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
        case .tone: return .systemPurple
        case .clarity: return .systemOrange
        case .rephrase: return .systemTeal
        }
    }

    nonisolated static func isDashedForSource(_ source: SuggestionSource) -> Bool {
        switch source {
        case .harper: return false
        case .llm: return true
        }
    }

    /// PLL-01: LLM suggestions render purple regardless of category;
    /// Harper suggestions use the existing category color.
    nonisolated static func colorForSuggestion(_ suggestion: Suggestion) -> NSColor {
        if suggestion.source == .llm { return .systemPurple }
        return colorForCategory(suggestion.category)
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
