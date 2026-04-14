@preconcurrency import ApplicationServices
import AppKit

/// Validates and transforms AX-returned CGRect values into AppKit-coordinate NSRects.
///
/// All methods are stateless given the same watchdog and quirks table. Pass custom
/// instances in tests to avoid shared state between parallel test cases.
struct BoundsValidator {

    static let minimumBoundsWidth: CGFloat = 2
    static let minimumBoundsHeight: CGFloat = 2
    static let maximumBoundsWidth: CGFloat = 800
    static let maximumBoundsHeight: CGFloat = 200

    private let watchdog: AXCallWatchdog
    private let quirksTable: AppQuirksTable

    init(watchdog: AXCallWatchdog = .shared, quirksTable: AppQuirksTable = .shared) {
        self.watchdog = watchdog
        self.quirksTable = quirksTable
    }

    // MARK: - Public API

    /// Validates AX bounds for a suggestion's character range.
    ///
    /// Returns nil if:
    /// - The watchdog says to skip this app's bundle ID.
    /// - The AX call fails or returns a non-CGRect value.
    /// - The returned rect fails size or sanity checks.
    ///
    /// Returns one NSRect per visual line in AppKit coordinates (y=0 at top-left).
    func validatedBoundsForRange(
        _ suggestion: Suggestion,
        in text: String,
        element: AXUIElement,
        bundleID: String,
        accessor: any AXAccessor
    ) -> [NSRect]? {
        guard !watchdog.shouldSkip(for: bundleID) else { return nil }

        let cfRange = cfRangeFor(suggestion, in: text)
        guard let cgRect = fetchRawBounds(cfRange: cfRange, element: element, bundleID: bundleID, attribute: kAXBoundsForRangeParameterizedAttribute, accessor: accessor) else {
            return nil
        }

        guard isValidRect(cgRect) else { return nil }

        // Apply per-app coordinate offsets when a quirk is registered.
        var adjustedRect = cgRect
        if let quirk = quirksTable.quirk(for: bundleID) {
            adjustedRect.origin.x += quirk.coordinateOffsetX ?? 0
            adjustedRect.origin.y += quirk.coordinateOffsetY ?? 0
        }

        // Estimate typical line height from a single character at the start of the range.
        let lineHeight = estimatedLineHeight(
            element: element,
            at: cfRange.location,
            bundleID: bundleID,
            fallback: adjustedRect.height,
            accessor: accessor
        )

        let quirk = quirksTable.quirk(for: bundleID)
        let strategy = quirk?.boundsStrategy ?? "rangeBounds"
        let lineHeightFactor = quirk?.lineHeightFactor ?? 1.0
        let threshold = lineHeight * lineHeightFactor * 1.5

        if strategy != "skipMultiLine" && adjustedRect.height > threshold {
            if let rects = splitMultiLine(
                element: element,
                range: cfRange,
                overallRect: adjustedRect,
                bundleID: bundleID,
                accessor: accessor
            ) {
                return rects
            }
        }

        return [flipCGRect(adjustedRect)]
    }

    // MARK: - Private: AX fetching

    private func fetchRawBounds(
        cfRange: CFRange,
        element: AXUIElement,
        bundleID: String,
        attribute: String,
        accessor: any AXAccessor
    ) -> CGRect? {
        var mutableRange = cfRange
        guard let axRangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        watchdog.beginCall(bundleID: bundleID, attribute: attribute)
        defer { watchdog.endCall() }
        let (error, ref) = accessor.copyParameterizedAttributeValue(element, attribute, axRangeValue)

        guard error == .success, let ref else { return nil }

        // Guard CFTypeID before casting — AX can return unexpected types (T-06-03).
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func fetchLineNumber(
        element: AXUIElement,
        charIndex: Int,
        bundleID: String,
        accessor: any AXAccessor
    ) -> Int? {
        // kAXLineForIndexParameterizedAttribute takes and returns NSNumber (CFNumber), not AXValue.
        let axIndex = NSNumber(value: charIndex) as CFTypeRef

        watchdog.beginCall(bundleID: bundleID, attribute: kAXLineForIndexParameterizedAttribute)
        defer { watchdog.endCall() }
        let (error, ref) = accessor.copyParameterizedAttributeValue(element, kAXLineForIndexParameterizedAttribute, axIndex)

        guard error == .success, let ref else { return nil }
        guard let lineNumber = ref as? NSNumber else { return nil }
        return lineNumber.intValue
    }

    private func fetchRangeForLine(
        element: AXUIElement,
        lineNumber: Int,
        bundleID: String,
        accessor: any AXAccessor
    ) -> CFRange? {
        // kAXRangeForLineParameterizedAttribute takes NSNumber (CFNumber), returns AXValue with .cfRange.
        let axLineIdx = NSNumber(value: lineNumber) as CFTypeRef

        watchdog.beginCall(bundleID: bundleID, attribute: kAXRangeForLineParameterizedAttribute)
        defer { watchdog.endCall() }
        let (error, ref) = accessor.copyParameterizedAttributeValue(element, kAXRangeForLineParameterizedAttribute, axLineIdx)

        guard error == .success, let ref else { return nil }
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }

        var lineRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(ref as! AXValue, .cfRange, &lineRange) else { return nil }
        return lineRange
    }

    // MARK: - Private: Multi-line splitting

    private func splitMultiLine(
        element: AXUIElement,
        range: CFRange,
        overallRect: CGRect,
        bundleID: String,
        accessor: any AXAccessor
    ) -> [NSRect]? {
        let startIdx = range.location
        let endIdx = range.location + range.length - 1

        guard let startLine = fetchLineNumber(element: element, charIndex: startIdx, bundleID: bundleID, accessor: accessor),
              let endLine = fetchLineNumber(element: element, charIndex: max(endIdx, startIdx), bundleID: bundleID, accessor: accessor) else {
            // Fallback: Y-coordinate sampling when AXLineForIndex is unavailable.
            return splitByYSampling(element: element, range: range, overallRect: overallRect, bundleID: bundleID, accessor: accessor)
        }

        var rects: [NSRect] = []

        for lineNum in startLine...endLine {
            guard let lineRange = fetchRangeForLine(element: element, lineNumber: lineNum, bundleID: bundleID, accessor: accessor) else {
                continue
            }

            // Intersect the error range with this line's range.
            let intersectStart = max(range.location, lineRange.location)
            let intersectEnd = min(range.location + range.length, lineRange.location + lineRange.length)
            guard intersectEnd > intersectStart else { continue }

            let intersectedRange = CFRange(location: intersectStart, length: intersectEnd - intersectStart)
            guard let lineRect = fetchRawBounds(cfRange: intersectedRange, element: element, bundleID: bundleID, attribute: kAXBoundsForRangeParameterizedAttribute, accessor: accessor) else {
                continue
            }
            guard isValidRect(lineRect) else { continue }
            rects.append(flipCGRect(lineRect))
        }

        return rects.isEmpty ? nil : rects
    }

    private func splitByYSampling(
        element: AXUIElement,
        range: CFRange,
        overallRect: CGRect,
        bundleID: String,
        accessor: any AXAccessor
    ) -> [NSRect]? {
        // Sample single-char bounds at intervals across the range.
        let step = max(1, range.length / 10)
        var samplesByY: [CGFloat: (minX: CGFloat, maxX: CGFloat, y: CGFloat, height: CGFloat)] = [:]
        let lineHeightTolerance: CGFloat = overallRect.height / 2

        var idx = 0
        while idx < range.length {
            let sampleRange = CFRange(location: range.location + idx, length: 1)
            if let sampleRect = fetchRawBounds(cfRange: sampleRange, element: element, bundleID: bundleID, attribute: kAXBoundsForRangeParameterizedAttribute, accessor: accessor),
               isValidRect(sampleRect) {
                // Find an existing Y-group within tolerance.
                if let existingY = samplesByY.keys.first(where: { abs($0 - sampleRect.origin.y) < lineHeightTolerance }) {
                    var group = samplesByY[existingY]!
                    group.minX = min(group.minX, sampleRect.origin.x)
                    group.maxX = max(group.maxX, sampleRect.maxX)
                    samplesByY[existingY] = group
                } else {
                    samplesByY[sampleRect.origin.y] = (
                        minX: sampleRect.origin.x,
                        maxX: sampleRect.maxX,
                        y: sampleRect.origin.y,
                        height: sampleRect.height
                    )
                }
            }
            idx += step
        }

        let rects = samplesByY.values
            .sorted { $0.y < $1.y }
            .map { group -> NSRect in
                let cgRect = CGRect(x: group.minX, y: group.y, width: group.maxX - group.minX, height: group.height)
                return flipCGRect(cgRect)
            }
            .filter { $0.width >= Self.minimumBoundsWidth }

        return rects.isEmpty ? nil : rects
    }

    // MARK: - Private: Helpers

    private func estimatedLineHeight(
        element: AXUIElement,
        at charIndex: Int,
        bundleID: String,
        fallback: CGFloat,
        accessor: any AXAccessor
    ) -> CGFloat {
        let singleCharRange = CFRange(location: charIndex, length: 1)
        if let singleRect = fetchRawBounds(cfRange: singleCharRange, element: element, bundleID: bundleID, attribute: kAXBoundsForRangeParameterizedAttribute, accessor: accessor),
           isValidRect(singleRect) {
            return singleRect.height
        }
        return fallback
    }

    private func cfRangeFor(_ suggestion: Suggestion, in text: String) -> CFRange {
        let scalars = text.unicodeScalars
        let location = scalars.distance(from: scalars.startIndex, to: suggestion.range.lowerBound)
        let length = scalars.distance(from: suggestion.range.lowerBound, to: suggestion.range.upperBound)
        return CFRange(location: location, length: length)
    }

    private func flipCGRect(_ cgRect: CGRect) -> NSRect {
        // Use the primary screen (origin == .zero), not NSScreen.main which is the key-window screen.
        // This matches how AX coordinates are defined: always relative to the bottom-left of
        // the primary display, regardless of which screen the window is on.
        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
        return NSRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    private func isValidRect(_ rect: CGRect) -> Bool {
        guard !rect.origin.x.isNaN, !rect.origin.y.isNaN,
              !rect.origin.x.isInfinite, !rect.origin.y.isInfinite else { return false }
        guard rect.width >= Self.minimumBoundsWidth,
              rect.height >= Self.minimumBoundsHeight else { return false }
        guard rect.width < Self.maximumBoundsWidth,
              rect.height < Self.maximumBoundsHeight else { return false }
        return true
    }
}
