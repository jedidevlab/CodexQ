import Foundation
import Testing
@testable import CodexQ

@Suite("TokenHistoryViewTests")
struct TokenHistoryViewTests {
    @Test("历史入口显示 Token 活动并位于设置与刷新之间")
    func historyButtonUsesActivityLabel() throws {
        let source = try text("Sources/CodexQ/Views/QuotaPopoverView.swift")
        let settings = try #require(source.range(of: "Button(action: showSettings)"))
        let history = try #require(source.range(of: "Button(action: showTokenHistory)"))
        let refresh = try #require(source.range(of: "Task { await store.refreshFromButton() }"))

        #expect(settings.lowerBound < history.lowerBound)
        #expect(history.lowerBound < refresh.lowerBound)
        #expect(source.contains(".help(\"Token 活动\")"))
        #expect(!source.contains(".help(\"Token 使用与成本\")"))
    }

    @Test("独立窗口和页面标题统一为 Token 活动")
    func windowAndViewUseActivityTitle() throws {
        let windowSource = try text("Sources/CodexQ/App/TokenHistoryWindowController.swift")
        let viewSource = try text("Sources/CodexQ/Views/TokenHistoryView.swift")

        #expect(windowSource.contains("window.title = \"Token 活动\""))
        #expect(viewSource.contains("Text(\"Token 活动\")"))
        #expect(!viewSource.contains("API 价格估算"))
    }

    @Test("历史页仅展示 Token 总量、日均和 Token 趋势")
    func historyViewRemovesCostAndModelPresentation() throws {
        let source = try text("Sources/CodexQ/Views/TokenHistoryView.swift")

        #expect(source.contains("title: \"Token 总量\""))
        #expect(source.contains("title: \"日均 Token\""))
        #expect(source.contains("TokenUsageHistoryChart("))
        #expect(!source.contains("title: \"估算成本\""))
        #expect(!source.contains("title: \"日均成本\""))
        #expect(!source.contains("TokenModelBreakdownChart("))
        #expect(!source.contains("TokenCostHistoryChart("))
    }

    @Test("历史读取器不再读取成本记录")
    func historyReaderUsesOnlyAccountActivity() throws {
        let source = try text("Sources/CodexQ/Services/TokenHistoryReader.swift")

        #expect(source.contains("let readActivity"))
        #expect(!source.contains("readCostRecords"))
        #expect(source.contains("records: []"))
        #expect(source.contains("dataScope: .account"))
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}
