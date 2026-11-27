import AppKit
import ApplicationServices

struct TextRunStrategy: GeometryProvider {
    let strategyName = "TextRuns"
    let strategyType: StrategyType = .textRuns
    let tier: StrategyTier = .precise
    let tierPriority = 0

    func canHandle(element _: AXUIElement, bundleID: String) -> Bool {
        AppRegistry.shared.configuration(for: bundleID).preferredStrategies.contains(.textRuns)
    }

    func calculateGeometry(
        errorRange: NSRange,
        element: AXUIElement,
        text: String,
        parser: ContentParser
    ) -> GeometryResult? {
        guard errorRange.length > 0,
              let utf16Range = TextIndexConverter.scalarRangeToUTF16CFRange(
                  start: errorRange.location,
                  end: NSMaxRange(errorRange),
                  in: text
              ),
              let token = AXWatchdog.shared.tryBeginCall(bundleID: AXClient.bundleIdentifier(for: element), attribute: "TextRunBounds")
        else { return nil }
        defer { AXWatchdog.shared.endCall(token) }

        let target = NSRange(location: utf16Range.location, length: utf16Range.length)
        let source = text as NSString
        var runs = [element]
        var offset = 0
        var remaining = 512
        var coveredLength = 0
        var bounds = CGRect.null

        // Chromium can expose precise bounds on static-text children even when the editor returns an empty rect.
        while let run = runs.popLast(), remaining > 0 {
            remaining -= 1
            let role = attribute(kAXRoleAttribute, in: run) as? String
            if role != kAXStaticTextRole as String {
                let children = attribute(kAXChildrenAttribute, in: run) as? [AXUIElement] ?? []
                runs.append(contentsOf: children.prefix(max(0, remaining - runs.count)).reversed())
                continue
            }

            guard let value = attribute(kAXValueAttribute, in: run) as? String, !value.isEmpty else { continue }
            guard let runRange = Self.matchRun(value, in: source, at: offset) else { return nil }
            offset = NSMaxRange(runRange)

            let overlap = NSIntersectionRange(target, runRange)
            if overlap.length > 0 {
                let local = NSRange(location: overlap.location - runRange.location, length: overlap.length)
                guard let rect = singleLineBounds(for: local, in: run),
                      bounds.isNull || Self.shareLine(bounds, rect)
                else { return nil }
                if let composer = parser as? T3CodeContentParser {
                    composer.scrollAnchor = (element, run, local, rect)
                }
                bounds = bounds.union(rect)
                coveredLength += overlap.length
            }
            if offset >= NSMaxRange(target) { break }
        }

        guard coveredLength == target.length, !bounds.isNull,
              bounds.height < GeometryConstants.conservativeMaxLineHeight
        else { return nil }
        return GeometryResult(
            bounds: CoordinateMapper.toCocoaCoordinates(bounds),
            confidence: GeometryConstants.highConfidence,
            strategy: strategyName,
            metadata: [:]
        )
    }

    /// A wrapped AX range is a bounding rectangle, which cannot describe two underline segments.
    private func singleLineBounds(for range: NSRange, in run: AXUIElement) -> CGRect? {
        guard let bounds = AccessibilityBridge.getBoundsForRange(range, in: run) else { return nil }
        if range.length == 1 { return bounds }

        let firstCharacter = NSRange(location: range.location, length: 1)
        let lastCharacter = NSRange(location: NSMaxRange(range) - 1, length: 1)
        guard let first = AccessibilityBridge.getBoundsForRange(firstCharacter, in: run, minSize: 0),
              let last = AccessibilityBridge.getBoundsForRange(lastCharacter, in: run, minSize: 0),
              Self.shareLine(first, last)
        else { return nil }
        return bounds
    }

    static func shareLine(_ first: CGRect, _ second: CGRect) -> Bool {
        max(first.minY, second.minY) < min(first.maxY, second.maxY)
    }

    /// AXValue inserts line breaks between runs. Match the next run in order so repeated words
    /// and folded sections cannot silently send an underline to a different occurrence.
    static func matchRun(_ run: String, in text: NSString, at offset: Int) -> NSRange? {
        var start = offset
        while start < text.length {
            let available = NSRange(location: start, length: text.length - start)
            let match = text.range(of: run, options: [.anchored, .literal], range: available)
            if match.location != NSNotFound { return match }
            let character = text.character(at: start)
            guard character == 10 || character == 13 else { return nil }
            start += 1
        }
        return nil
    }

    private func attribute(_ name: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
