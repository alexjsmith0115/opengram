import AppKit

/// Data model for a single underline rendered by UnderlineView.
struct UnderlineEntry {
    let underlineRect: NSRect
    let hitRect: NSRect
    let highlightRect: NSRect
    let suggestion: Suggestion

    init(
        underlineRect: NSRect,
        hitRect: NSRect,
        suggestion: Suggestion,
        highlightRect: NSRect? = nil
    ) {
        self.underlineRect = underlineRect
        self.hitRect = hitRect
        self.highlightRect = highlightRect ?? Self.defaultHighlightRect(from: underlineRect)
        self.suggestion = suggestion
    }

    nonisolated static func defaultHighlightRect(from underlineRect: NSRect) -> NSRect {
        let horizontalOutset: CGFloat = 2
        let height: CGFloat = 16
        return NSRect(
            x: underlineRect.minX - horizontalOutset,
            y: underlineRect.minY,
            width: underlineRect.width + (horizontalOutset * 2),
            height: height
        )
    }

    var clickRect: NSRect {
        hitRect.union(highlightRect)
    }
}

/// NSView subclass that renders colored underlines over flagged text ranges.
/// Overrides hitTest to pass non-underline clicks through to the target app.
@MainActor
final class UnderlineView: NSView {

    private struct HoverAnimation {
        let startTime: TimeInterval
        let startProgress: CGFloat
        let targetProgress: CGFloat
    }

    private static let hoverAnimationDuration: TimeInterval = 0.12

    var entries: [UnderlineEntry] = [] {
        didSet {
            if let activeHighlightID,
               !entries.contains(where: { $0.suggestion.id == activeHighlightID }) {
                setHoveredSuggestionID(nil, animated: false)
            }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onClick: ((Suggestion) -> Void)?
    private(set) var hoveredSuggestionID: UUID?
    private var activeHighlightID: UUID?
    private var hoverProgress: CGFloat = 0
    private var hoverAnimation: HoverAnimation?
    private var hoverTimer: Timer?

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

        drawHoverHighlights(for: sorted)

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
        return entryAt(point: localPoint) == nil ? nil : self
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
        entryAt(point: point)?.suggestion
    }

    func hoveredSuggestionAt(point: NSPoint) -> Suggestion? {
        entryAt(point: point)?.suggestion
    }

    func setHoveredSuggestionID(_ suggestionID: UUID?, animated: Bool = true) {
        guard hoveredSuggestionID != suggestionID else { return }

        hoveredSuggestionID = suggestionID

        if let suggestionID {
            activeHighlightID = suggestionID
            hoverProgress = 0
            startHoverAnimation(to: 1, animated: animated)
        } else {
            startHoverAnimation(to: 0, animated: animated)
        }
    }

    override func resetCursorRects() {
        for entry in entries {
            addCursorRect(entry.clickRect, cursor: .pointingHand)
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

    nonisolated static func highlightColorForSuggestion(_ suggestion: Suggestion) -> NSColor {
        colorForSuggestion(suggestion).withAlphaComponent(0.16)
    }

    nonisolated static func highlightRect(from textRect: NSRect, underlineRect: NSRect) -> NSRect {
        let horizontalOutset: CGFloat = 2
        let minimumHeight: CGFloat = 14
        return NSRect(
            x: underlineRect.minX - horizontalOutset,
            y: underlineRect.minY,
            width: underlineRect.width + (horizontalOutset * 2),
            height: max(textRect.height, minimumHeight)
        )
    }

    /// Expands the clickable underline affordance. The overlay window stays
    /// mouse-transparent, so this can be forgiving without blocking text editing.
    nonisolated static func expandedHitRect(from underlineRect: NSRect) -> NSRect {
        let verticalOutset: CGFloat = 6
        return NSRect(
            x: underlineRect.minX,
            y: underlineRect.minY - verticalOutset,
            width: underlineRect.width,
            height: underlineRect.height + (verticalOutset * 2)
        )
    }

    private func drawHoverHighlights(for sortedEntries: [UnderlineEntry]) {
        guard let activeHighlightID, hoverProgress > 0 else { return }
        let clampedProgress = min(max(hoverProgress, 0), 1)

        for entry in sortedEntries where entry.suggestion.id == activeHighlightID {
            let fullRect = entry.highlightRect
            let animatedRect = NSRect(
                x: fullRect.minX,
                y: fullRect.minY,
                width: fullRect.width,
                height: fullRect.height * clampedProgress
            )
            let color = Self.highlightColorForSuggestion(entry.suggestion)
            color.setFill()
            NSBezierPath(roundedRect: animatedRect, xRadius: 2.5, yRadius: 2.5).fill()
        }
    }

    private func entryAt(point: NSPoint) -> UnderlineEntry? {
        if let underlined = entriesForHitTesting().first(where: { $0.hitRect.contains(point) }) {
            return underlined
        }
        return entriesForHitTesting().first(where: { $0.highlightRect.contains(point) })
    }

    private func entriesForHitTesting() -> [UnderlineEntry] {
        entries.sorted { a, b in
            let aOrder = (a.suggestion.source == .llm) ? 0 : 1
            let bOrder = (b.suggestion.source == .llm) ? 0 : 1
            return aOrder > bOrder
        }
    }

    private func startHoverAnimation(to targetProgress: CGFloat, animated: Bool) {
        hoverTimer?.invalidate()
        hoverTimer = nil

        guard animated else {
            hoverProgress = targetProgress
            if targetProgress == 0 {
                activeHighlightID = nil
            }
            hoverAnimation = nil
            needsDisplay = true
            return
        }

        hoverAnimation = HoverAnimation(
            startTime: ProcessInfo.processInfo.systemUptime,
            startProgress: hoverProgress,
            targetProgress: targetProgress
        )

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepHoverAnimation()
            }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    private func stepHoverAnimation() {
        guard let hoverAnimation else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - hoverAnimation.startTime
        let linearProgress = min(1, elapsed / Self.hoverAnimationDuration)
        let easedProgress = 1 - pow(1 - linearProgress, 3)
        hoverProgress = hoverAnimation.startProgress
            + ((hoverAnimation.targetProgress - hoverAnimation.startProgress) * easedProgress)
        needsDisplay = true

        guard linearProgress >= 1 else { return }

        self.hoverAnimation = nil
        hoverProgress = hoverAnimation.targetProgress
        if hoverAnimation.targetProgress == 0 {
            activeHighlightID = nil
        }
        hoverTimer?.invalidate()
        hoverTimer = nil
        needsDisplay = true
    }
}
