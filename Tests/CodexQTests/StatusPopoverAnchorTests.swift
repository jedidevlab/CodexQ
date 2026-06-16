import AppKit
import Testing
@testable import CodexQ

struct StatusPopoverAnchorTests {
    @Test("弹窗锚定在图标区域而不是整个状态栏按钮")
    @MainActor
    func anchorUsesLeadingIconRect() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 72, height: 22))
        button.image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in true }
        button.title = "46%"
        button.imagePosition = .imageLeading

        let anchor = StatusPopoverAnchor.rect(for: button)

        #expect(anchor.width > 0)
        #expect(anchor.midX < button.bounds.midX)
    }
}
