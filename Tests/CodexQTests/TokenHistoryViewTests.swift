import Foundation
import Testing
@testable import CodexQ

@Suite("TokenHistoryViewTests")
struct TokenHistoryViewTests {
    @Test("两个标题共用同一历史窗口路由且窗口保留用户尺寸")
    func titlesShareOneWindowRoute() throws {
        let popoverSource = try source("Sources/CodexQ/Views/QuotaPopoverView.swift")
        let controllerSource = try source("Sources/CodexQ/App/StatusBarController.swift")
        let windowSource = try source("Sources/CodexQ/App/TokenHistoryWindowController.swift")
        let activitySource = try source("Sources/CodexQ/Views/TokenActivitySection.swift")
        let costSource = try source("Sources/CodexQ/Views/TokenCostSection.swift")

        #expect(popoverSource.contains("let showTokenHistory: () -> Void"))
        #expect(popoverSource.components(separatedBy: "showHistory: showTokenHistory").count - 1 == 2)
        #expect(controllerSource.contains(
            "private var tokenHistoryWindowController: TokenHistoryWindowController?"
        ))
        #expect(controllerSource.contains("private func showTokenHistoryWindow()"))
        #expect(controllerSource.contains("panel.orderOut(nil)"))
        #expect(windowSource.contains("window.title = \"Token 使用与成本\""))
        #expect(windowSource.contains("window.isReleasedWhenClosed = false"))
        #expect(windowSource.contains("window.minSize = NSSize(width: 760, height: 560)"))
        #expect(windowSource.contains("window.setFrameAutosaveName(\"TokenHistoryWindow\")"))
        #expect(windowSource.contains("hostingController.sizingOptions = []"))
        #expect(activitySource.contains(".help(\"点击查看 Token 使用与成本历史\")"))
        #expect(costSource.contains(".help(\"点击查看 Token 使用与成本历史\")"))
    }

    @Test("历史页包含五种筛选、摘要、数据说明和完整图表契约")
    func historyViewContainsRequestedContracts() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

        #expect(viewSource.contains("ForEach(TokenHistoryRangeMode.allCases)"))
        #expect(viewSource.contains("DatePicker(\"日期\""))
        #expect(viewSource.contains("DatePicker(\"开始\""))
        #expect(viewSource.contains("DatePicker(\"结束\""))
        #expect(viewSource.contains("Picker(\"订阅周期\""))
        #expect(viewSource.contains("title: \"Token 总量\""))
        #expect(viewSource.contains("title: \"估算成本\""))
        #expect(viewSource.contains("title: \"日均 Token\""))
        #expect(viewSource.contains("title: \"日均成本\""))
        #expect(viewSource.contains("API 价格估算，非实际订阅账单"))
        #expect(viewSource.contains("按当前续费日推算"))
        #expect(viewSource.contains("未计价 Token"))
        #expect(chartSource.contains("import Charts"))
        #expect(chartSource.contains("struct TokenUsageHistoryChart"))
        #expect(chartSource.contains("BarMark("))
        #expect(chartSource.contains("struct TokenCostHistoryChart"))
        #expect(chartSource.contains("LineMark("))
        #expect(chartSource.contains("AreaMark("))
        #expect(chartSource.contains("RuleMark("))
        #expect(chartSource.contains("struct TokenModelBreakdownChart"))
        #expect(chartSource.contains("chartXSelection"))
        #expect(!chartSource.contains("SectorMark("))
        #expect(!chartSource.contains("dualAxis"))
    }

    @Test("十个模型压缩为前八名加其他且总量守恒")
    func compactsModelsWithoutLosingTotals() {
        let models = (1...10).map { value in
            TokenHistoryModelSummary(
                model: "model-\(value)",
                totalTokens: Int64(value * 100),
                estimatedCostUSD: Double(value)
            )
        }

        let compacted = TokenHistoryModelCompactor.compact(models)

        #expect(compacted.count == 9)
        #expect(compacted.last?.model == "其他")
        #expect(compacted.reduce(Int64(0)) { $0 + $1.totalTokens }
            == models.reduce(Int64(0)) { $0 + $1.totalTokens })
        #expect(compacted.compactMap(\.estimatedCostUSD).reduce(0, +)
            == models.compactMap(\.estimatedCostUSD).reduce(0, +))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}
