import AppKit
import Testing
@testable import CodexQ

struct StatusPanelPositionerTests {
    @Test("弹窗使用更厚的系统材质与描边隔离桌面背景")
    func panelUsesLegibleSystemMaterial() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        #expect(source.contains("panel.hasShadow = false"))
        #expect(source.contains(".background(.thickMaterial"))
        #expect(source.contains(".stroke(Color.primary.opacity(0.14), lineWidth: 1)"))
        #expect(!source.contains(".background(.regularMaterial"))
    }

    @Test("面板使用内容 fitting 高度而不是初始二百五十像素")
    func fittedSizePreservesBaseActivityAndTallContentHeights() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        for height in [230.0, 343.0, 520.0] {
            let size = StatusPanelPositioner.fittedSize(
                contentSize: NSSize(width: 316, height: height),
                visibleFrame: visibleFrame
            )

            #expect(size == NSSize(width: 316, height: height))
        }
    }

    @Test("内容高度变化后面板顶边保持菜单栏锚定")
    func fittedHeightChangesKeepTopEdgeStable() {
        let anchor = NSRect(x: 500, y: 900, width: 24, height: 22)
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let base = StatusPanelPositioner.frame(
            panelSize: StatusPanelPositioner.fittedSize(
                contentSize: NSSize(width: 316, height: 230),
                visibleFrame: visible
            ),
            anchorRect: anchor,
            visibleFrame: visible
        )
        let tall = StatusPanelPositioner.frame(
            panelSize: StatusPanelPositioner.fittedSize(
                contentSize: NSSize(width: 316, height: 520),
                visibleFrame: visible
            ),
            anchorRect: anchor,
            visibleFrame: visible
        )

        #expect(base.maxY == tall.maxY)
        #expect(tall.height == 520)
        #expect(tall.minY >= visible.minY)
    }

    @Test("控制器在展示前和内容变化后重新 fitting")
    func controllerRefitsForPresentationAndPublishedContent() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        #expect(source.contains("sizeThatFits(in:"))
        #expect(source.contains("fitPanel("))
        #expect(source.contains("store.$tokenActivity"))
        #expect(source.contains("store.$tokenActivityErrorMessage"))
        #expect(source.contains("schedulePanelRefit()"))
        let fitIndex = try #require(source.range(of: "fitPanel(anchorRect:"))
        let showIndex = try #require(source.range(of: "panel.orderFrontRegardless()"))
        #expect(fitIndex.lowerBound < showIndex.lowerBound)
    }

    @Test("控制器按刷新与交互状态统一管理自动关闭")
    func controllerUsesInteractionAwareAutoClosePolicy() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        #expect(source.contains("activeInteractions"))
        #expect(source.contains("interactionDidChange"))
        #expect(source.contains("PopoverAutoClosePolicy.shouldSchedule"))
        #expect(source.contains("activeInteractions.removeAll()"))
    }

    @Test("弹窗失去焦点后仍立即关闭")
    func panelStillClosesWhenItResignsKey() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusPanel.swift",
            encoding: .utf8
        )

        #expect(source.contains("override func resignKey()"))
        #expect(source.contains("self.orderOut(nil)"))
    }

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
