import Foundation
import Testing
@testable import CodexQ

struct StatusBarControllerTests {
    @Test("成本明细交互冻结中间帧并同步完成无动画窗口调整")
    func interactiveRefitIsAtomic() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        let callbackStart = try #require(source.range(of: "contentDidChange: {"))
        let callbackEnd = try #require(
            source.range(
                of: "interactionDidChange:",
                range: callbackStart.upperBound..<source.endIndex
            )
        )
        let callbackSource = source[callbackStart.lowerBound..<callbackEnd.lowerBound]

        #expect(callbackSource.contains("refitPanelImmediately()"))
        #expect(callbackSource.contains("preparePanelForInteractiveRefit()"))
        #expect(source.contains("panel.disableScreenUpdatesUntilFlush()"))
        #expect(source.contains("animate: false"))
    }

    @Test("控制器禁用 SwiftUI 自动窗口尺寸，避免超高内容覆盖锚定后的面板尺寸")
    func controllerOwnsPanelSizing() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        let controllerCreation = try #require(
            source.range(of: "let hostingController = NSHostingController(rootView: rootView)")
        )
        let sizingOptions = try #require(
            source.range(
                of: "hostingController.sizingOptions = []",
                range: controllerCreation.upperBound..<source.endIndex
            )
        )
        let panelAssignment = try #require(
            source.range(
                of: "panel.contentViewController = hostingController",
                range: controllerCreation.upperBound..<source.endIndex
            )
        )

        #expect(sizingOptions.lowerBound < panelAssignment.lowerBound)
    }

    @Test("设置使用独立窗口，并在展示前关闭菜单面板")
    func settingsUseDedicatedWindow() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOfFile: "Sources/CodexQ/App/SettingsWindowController.swift",
            encoding: .utf8
        )
        let methodStart = try #require(source.range(of: "private func showSettingsWindow()"))
        let methodEnd = try #require(
            source.range(of: "private func panelDidClose()", range: methodStart.upperBound..<source.endIndex)
        )
        let methodSource = source[methodStart.lowerBound..<methodEnd.lowerBound]
        let closePanel = try #require(methodSource.range(of: "panel.orderOut(nil)"))
        let showSettings = try #require(methodSource.range(of: "controller.present()"))

        #expect(closePanel.lowerBound < showSettings.lowerBound)
        #expect(settingsSource.contains("window.title = \"CodexQ 设置\""))
        #expect(settingsSource.contains("SettingsWindowView(store: store, settings: settings)"))
    }

    @Test("内容变化时沿用首次展示锚点，避免面板随状态栏标题漂移")
    func refitKeepsPresentationAnchor() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        let refitStart = try #require(source.range(of: "private func schedulePanelRefit()"))
        let refitEnd = try #require(
            source.range(of: "private func currentPanelPosition", range: refitStart.upperBound..<source.endIndex)
        )
        let refitSource = source[refitStart.lowerBound..<refitEnd.lowerBound]

        #expect(refitSource.contains("let anchorRect = self.currentAnchorRect"))
        #expect(refitSource.contains("let visibleFrame = self.currentVisibleFrame"))
        #expect(!refitSource.contains("currentPanelPosition(for:"))
    }
}
