import AppKit
import Testing
@testable import CodexQ

struct StatusIconRendererTests {
    @Test("菜单栏图标不随额度裁切")
    @MainActor
    func iconIsNotClippedByRemainingPercent() throws {
        let source = NSImage(size: NSSize(width: 10, height: 10))
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: source.size).fill()
        source.unlockFocus()

        let lowQuota = StatusIconRenderer.image(source: source, remainingPercent: 10)
        let fullQuota = StatusIconRenderer.image(source: source, remainingPercent: 100)
        let lowQuotaAlpha = try alphaPixels(of: lowQuota)
        let fullQuotaAlpha = try alphaPixels(of: fullQuota)

        #expect(lowQuotaAlpha == fullQuotaAlpha)
        #expect(lowQuotaAlpha.contains { $0 > 0 })
    }

    private func alphaPixels(of image: NSImage) throws -> [UInt8] {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))

        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).map { x in
                UInt8((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255)
            }
        }
    }
}
