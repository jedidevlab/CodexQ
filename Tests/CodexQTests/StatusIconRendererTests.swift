import AppKit
import Testing
@testable import CodexQ

struct StatusIconRendererTests {
    @Test("菜单栏图标只在按钮初始化时设置")
    func statusItemImageIsNotReassignedDuringStatusUpdates() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )
        let updateStart = try #require(source.range(of: "private func updateStatusItem()"))
        let updateSource = source[updateStart.lowerBound...]

        #expect(source.contains("button.image = StatusIconRenderer.image("))
        #expect(!updateSource.contains("statusItem.button?.image ="))
    }

    @Test("菜单栏标题不重复写入相同值")
    func statusItemTitleOnlyChangesWhenNeeded() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        #expect(source.contains("if button.title != title"))
        #expect(source.contains("button.title = title"))
    }

    @Test("菜单栏按钮先设置 target 再设置 action")
    func statusItemConfiguresTargetBeforeAction() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )
        let targetIndex = try #require(source.range(of: "button.target = self"))
        let actionIndex = try #require(source.range(of: "button.action = #selector"))

        #expect(targetIndex.lowerBound < actionIndex.lowerBound)
    }

    @Test("锁屏时延后创建菜单栏状态项")
    func statusItemCreationWaitsForActiveSession() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/CodexQApp.swift",
            encoding: .utf8
        )

        #expect(source.contains("NSWorkspace.sessionDidBecomeActiveNotification"))
        #expect(source.contains("ScreenSessionState.isLocked"))
        #expect(source.contains("startStatusControllerIfNeeded()"))
    }

    @Test("会话字典能识别锁屏状态")
    func screenSessionStateDetectsLock() {
        #expect(ScreenSessionState.isLocked([
            "CGSSessionScreenIsLocked": true
        ]))
        #expect(!ScreenSessionState.isLocked([
            "CGSSessionScreenIsLocked": false
        ]))
        #expect(!ScreenSessionState.isLocked(nil))
    }

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

    @Test("菜单栏图标使用接近系统图标的可读尺寸")
    @MainActor
    func iconUsesLegibleStatusBarSize() throws {
        let source = NSImage(size: NSSize(width: 10, height: 10))
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: source.size).fill()
        source.unlockFocus()

        let rendered = StatusIconRenderer.image(source: source, remainingPercent: 100)
        #expect(rendered.size == NSSize(width: 20, height: 20))
        let data = try #require(rendered.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let visibleColumns = (0..<bitmap.pixelsWide).filter { x in
            (0..<bitmap.pixelsHigh).contains { y in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }

        #expect(visibleColumns.count >= 19)
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
