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
        #expect(windowSource.contains("window.minSize = NSSize(width: 840, height: 600)"))
        #expect(windowSource.contains("window.setFrameAutosaveName(\"TokenHistoryWindow\")"))
        #expect(windowSource.contains("hostingController.sizingOptions = []"))
        #expect(activitySource.contains(".help(\"点击查看 Token 使用与成本历史\")"))
        #expect(costSource.contains(".help(\"点击查看 Token 使用与成本历史\")"))
    }

    @Test("历史页包含六种筛选、摘要、数据说明和完整图表契约")
    func historyViewContainsRequestedContracts() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

        #expect(viewSource.contains("ForEach(TokenHistoryRangeMode.allCases)"))
        #expect(viewSource.contains("if let snapshot = store.visibleSnapshot"))
        #expect(viewSource.contains("TokenHistoryWeekDatePicker("))
        #expect(viewSource.contains("DatePicker(\"开始\""))
        #expect(viewSource.contains("DatePicker(\"结束\""))
        #expect(viewSource.contains("Picker(\"订阅周期\""))
        #expect(viewSource.contains(".fixedSize(horizontal: true, vertical: false)"))
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

    @Test("底部数据注释位于模型分布之后且未计价说明最后显示")
    func historyNotesFollowModelBreakdown() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let modelCall = try #require(
            viewSource.range(of: "TokenModelBreakdownChart(models: snapshot.models)")
        )
        let footerCall = try #require(viewSource.range(
            of: "footerNotes(snapshot)",
            range: modelCall.upperBound..<viewSource.endIndex
        ))
        let footerStart = try #require(
            viewSource.range(of: "private func footerNotes(_ snapshot: TokenHistorySnapshot)")
        )
        let footerEnd = try #require(viewSource.range(
            of: "private func qualityRow(_ snapshot: TokenHistorySnapshot)",
            range: footerStart.upperBound..<viewSource.endIndex
        ))
        let footerSource = viewSource[footerStart.lowerBound..<footerEnd.lowerBound]
        let quality = try #require(footerSource.range(of: "qualityRow(snapshot)"))
        let unpricedNote = try #require(
            footerSource.range(of: "未计价 Token：")
        )

        #expect(modelCall.lowerBound < footerCall.lowerBound)
        #expect(quality.lowerBound < unpricedNote.lowerBound)
        #expect(!viewSource.contains("private var contextRow: some View"))
    }

    @Test("价格估算提示紧邻标题且底部单独解释未计价 Token")
    func historyAnnotationsUseRequestedPositions() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let titleStart = try #require(viewSource.range(of: "private var titleRow: some View"))
        let titleEnd = try #require(viewSource.range(
            of: "private var rangeRow: some View",
            range: titleStart.upperBound..<viewSource.endIndex
        ))
        let titleSource = viewSource[titleStart.lowerBound..<titleEnd.lowerBound]
        let footerStart = try #require(
            viewSource.range(of: "private func footerNotes(_ snapshot: TokenHistorySnapshot)")
        )
        let footerEnd = try #require(viewSource.range(
            of: "private func qualityRow(_ snapshot: TokenHistorySnapshot)",
            range: footerStart.upperBound..<viewSource.endIndex
        ))
        let footerSource = viewSource[footerStart.lowerBound..<footerEnd.lowerBound]

        #expect(titleSource.contains("API 价格估算，非实际订阅账单"))
        #expect(!footerSource.contains("API 价格估算，非实际订阅账单"))
        #expect(footerSource.contains("缺少对应 API 价格"))
        #expect(footerSource.contains("计入 Token 总量，但不计入估算成本"))
    }

    @Test("月份选择器保留足够宽度完整显示月份")
    func monthPickerKeepsReadableWidth() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let monthStart = try #require(viewSource.range(of: "Picker(\"月份\""))
        let monthEnd = try #require(viewSource.range(
            of: "case .year:",
            range: monthStart.upperBound..<viewSource.endIndex
        ))
        let monthSource = viewSource[monthStart.lowerBound..<monthEnd.lowerBound]

        #expect(monthSource.contains(".frame(minWidth: 110)"))
        #expect(!monthSource.contains(".frame(width: 86)"))
    }

    @Test("日日期选择器直接控制输入框宽度")
    func dayPickerControlsDateFieldWidth() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let dayStart = try #require(viewSource.range(of: "case .day:"))
        let dayEnd = try #require(viewSource.range(
            of: "case .month:",
            range: dayStart.upperBound..<viewSource.endIndex
        ))
        let daySource = viewSource[dayStart.lowerBound..<dayEnd.lowerBound]

        #expect(daySource.contains("TokenHistoryWeekDatePicker("))
        #expect(daySource.contains(".frame(width: 124, height: 22)"))
        #expect(!daySource.contains("DatePicker(\"所在周\""))
        #expect(!daySource.contains(".frame(minWidth: 200)"))
    }

    @Test("订阅周期选择器按当前选项内容采用自身宽度")
    func subscriptionPickerUsesSelectedContentWidth() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let subscriptionStart = try #require(viewSource.range(of: "case .subscription:"))
        let subscriptionEnd = try #require(viewSource.range(
            of: "case .cumulative:",
            range: subscriptionStart.upperBound..<viewSource.endIndex
        ))
        let subscriptionSource = viewSource[
            subscriptionStart.lowerBound..<subscriptionEnd.lowerBound
        ]

        #expect(subscriptionSource.contains(
            ".fixedSize(horizontal: true, vertical: false)"
        ))
        #expect(!subscriptionSource.contains(".frame(width: 280)"))
    }

    @Test("历史窗口使用系统背景、分行筛选和统一摘要卡")
    func historyViewUsesAdaptiveDashboardLayout() throws {
        let windowSource = try source("Sources/CodexQ/App/TokenHistoryWindowController.swift")
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")

        #expect(windowSource.contains("width: 1080, height: 720"))
        #expect(windowSource.contains("window.minSize = NSSize(width: 840, height: 600)"))
        #expect(viewSource.contains("private var titleRow: some View"))
        #expect(viewSource.contains("private var rangeRow: some View"))
        #expect(viewSource.contains("private func footerNotes(_ snapshot: TokenHistorySnapshot)"))
        #expect(viewSource.contains("TokenHistoryCardSurface(cornerRadius: 12)"))
        #expect(viewSource.contains(".foregroundStyle(accent)"))
        #expect(!viewSource.contains(".background(color.opacity(0.08)"))
        #expect(!viewSource.contains("Color.black"))
        #expect(!viewSource.contains(".preferredColorScheme(.dark)"))
    }

    @Test("趋势图宽屏双栏且窄屏自动纵向回退")
    func historyChartsUseResponsiveTwoColumnLayout() throws {
        let viewSource = try source("Sources/CodexQ/Views/TokenHistoryView.swift")
        let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

        #expect(viewSource.contains("ResponsiveTokenHistoryCharts("))
        #expect(viewSource.contains("TokenModelBreakdownChart(models: snapshot.models)"))
        #expect(chartSource.contains("struct ResponsiveTokenHistoryCharts"))
        #expect(chartSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(chartSource.contains("HStack(alignment: .top, spacing: 16)"))
        #expect(chartSource.contains(".frame(minWidth: 900)"))
        #expect(chartSource.contains("VStack(alignment: .leading, spacing: 16)"))
        #expect(chartSource.contains("TokenHistoryCardSurface(cornerRadius: 12)"))
        #expect(!chartSource.contains(".background(.thinMaterial"))
    }

    @Test("趋势图悬浮提示只调整位置而不扩张标尺")
    func historyChartTooltipUsesStableOverflowResolution() throws {
        let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

        #expect(chartSource.components(
            separatedBy: "overflowResolution: .init("
        ).count - 1 == 2)
        #expect(chartSource.components(
            separatedBy: "x: .fit(to: .chart), y: .fit(to: .chart)"
        ).count - 1 == 2)
        #expect(!chartSource.contains(".padScale"))
    }

    @Test("模型分布使用独立文字列显示模型名称而非依赖图表坐标轴推断")
    func modelBreakdownUsesExplicitModelLabels() throws {
        let chartSource = try source("Sources/CodexQ/Views/TokenHistoryCharts.swift")

        #expect(chartSource.contains("struct TokenModelBreakdownRow: View"))
        #expect(chartSource.contains("Text(model.model)"))
        #expect(!chartSource.contains("if let modelName = value.as(String.self)"))
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
