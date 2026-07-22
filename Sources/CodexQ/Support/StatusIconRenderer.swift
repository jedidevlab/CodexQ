import AppKit

@MainActor
enum StatusIconRenderer {
    static func image(source: NSImage, remainingPercent _: Double) -> NSImage {
        let canvasSize = NSSize(width: 20, height: 20)
        let iconSize = NSSize(width: 20, height: 20)
        let iconRect = NSRect(
            x: (canvasSize.width - iconSize.width) / 2,
            y: (canvasSize.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        let image = NSImage(size: canvasSize)
        let sourceRect = NSRect(origin: .zero, size: source.size)

        image.lockFocus()
        defer { image.unlockFocus() }

        source.draw(
            in: iconRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )

        image.isTemplate = true
        return image
    }
}
