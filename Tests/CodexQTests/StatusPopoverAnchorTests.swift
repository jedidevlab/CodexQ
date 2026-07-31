import AppKit
import Testing
@testable import CodexQ

struct StatusPopoverAnchorTests {
    @Test("弹窗锚定在整个状态栏按钮，确保左边缘对齐")
    @MainActor
    func anchorUsesStatusItemButtonBounds() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 72, height: 22))
        button.image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in true }
        button.title = "46%"
        button.imagePosition = .imageLeading

        let anchor = StatusPopoverAnchor.rect(for: button)

        #expect(anchor == button.bounds)
    }
}
