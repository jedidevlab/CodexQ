import AppKit
import Testing
@testable import CodexQ

struct StatusPanelPositionerTests {
    @Test("面板在现有位置基础上整体向左偏移十像素")
    func panelOffsetsTenPixelsLeft() {
        let frame = StatusPanelPositioner.frame(
            panelSize: NSSize(width: 316, height: 250),
            anchorRect: NSRect(x: 500, y: 900, width: 24, height: 22),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.minX == 490)
        #expect(frame.maxY == 899)
    }

    @Test("面板不会超出当前屏幕右边缘")
    func panelStaysInsideVisibleFrame() {
        let frame = StatusPanelPositioner.frame(
            panelSize: NSSize(width: 316, height: 250),
            anchorRect: NSRect(x: 1420, y: 900, width: 20, height: 22),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.maxX == 1422)
    }
}
