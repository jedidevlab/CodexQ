import Foundation
import Testing
@testable import CodexQ

struct StatusBarControllerTests {
    @Test("内容变化时重新读取菜单栏锚点，避免状态栏标题变化后面板跳动")
    func refitUsesCurrentStatusItemAnchor() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/App/StatusBarController.swift",
            encoding: .utf8
        )

        #expect(source.contains("let button = self.statusItem.button"))
        #expect(source.contains("self.currentPanelPosition(for: button)"))
        #expect(source.contains("private func currentPanelPosition(for button: NSStatusBarButton)"))
    }
}
