import Foundation
import Testing
@testable import CodexQ

struct StatusBarControllerTests {
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
