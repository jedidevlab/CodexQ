import AppKit

enum StatusPanelPositioner {
    private static let edgeInset: CGFloat = 8
    private static let horizontalOffset: CGFloat = 10
    private static let menuBarGap: CGFloat = 1

    static func fittedSize(
        contentSize: NSSize,
        visibleFrame: NSRect
    ) -> NSSize {
        let maximumWidth = max(1, visibleFrame.width - edgeInset * 2)
        return NSSize(
            width: min(maximumWidth, max(1, contentSize.width)),
            height: max(1, contentSize.height)
        )
    }

    static func frame(
        panelSize: NSSize,
        anchorRect: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        let idealX = anchorRect.minX
        let minX = visibleFrame.minX + edgeInset
        let maxX = visibleFrame.maxX - edgeInset - panelSize.width
        let positionedX = min(maxX, max(minX, idealX))
        let x = max(minX, positionedX - horizontalOffset)
        let y = anchorRect.minY - menuBarGap - panelSize.height
        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}
