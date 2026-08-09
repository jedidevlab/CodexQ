import AppKit
import SwiftUI
import Testing
import Vision
@testable import CodexQ

@Suite("TokenHistoryRenderingTests", .serialized)
struct TokenHistoryRenderingTests {
    @Test("历史入口标题悬浮时使用可点击指针")
    @MainActor
    func historyNavigationTitleUsesPointingHandCursor() {
        NSCursor.arrow.set()
        defer { TokenHistoryNavigationCursor.update(isHovered: false) }

        TokenHistoryNavigationCursor.update(isHovered: true)

        #expect(NSCursor.current == NSCursor.pointingHand)
    }

    @Test("历史入口标题悬浮时文字明显变淡")
    @MainActor
    func historyNavigationTitleFadesOnHover() {
        let normal = render(
            TokenHistoryNavigationLabel(title: "Token 活动", isHovered: false),
            width: 120,
            height: 40
        )
        let hovered = render(
            TokenHistoryNavigationLabel(title: "Token 活动", isHovered: true),
            width: 120,
            height: 40
        )

        #expect(darkPixelCount(in: hovered) < darkPixelCount(in: normal))
    }

    @Test("日模式显示所在周且范围选择包含累计")
    @MainActor
    func dayModeShowsWeekContextAndCumulativeRange() throws {
        let store = TokenHistoryStore(now: { self.startDate }, calendar: calendar)
        store.mode = .day

        let observations = try recognizedText(
            in: render(TokenHistoryView(store: store), width: 840, height: 720)
        )

        let weekControl = try #require(observation(containing: "所在周", in: observations))
        let dateControl = try #require(observation(containing: "2026", in: observations))
        let dateControlText = try #require(dateControl.topCandidates(1).first?.string)
        #expect(dateControlText.contains("9"))
        #expect(abs(weekControl.boundingBox.midY - dateControl.boundingBox.midY) < 0.02)
        #expect(observation(containing: "累计", in: observations) != nil)
        #expect(observation(containing: "周", in: observations)?.topCandidates(1).first?.string != "周")
    }

    @Test("自定义日期控件与日期范围选择器保持同一行")
    @MainActor
    func customDateControlsStayOnRangeRow() throws {
        let store = TokenHistoryStore(now: { self.startDate }, calendar: calendar)
        store.mode = .custom

        let observations = try recognizedText(
            in: render(TokenHistoryView(store: store), width: 840, height: 600)
        )
        let rangeRow = try #require(observation(containing: "开始", in: observations))
        let rangeText = try #require(rangeRow.topCandidates(1).first?.string)
        let custom = try #require(observation(containing: "自定义", in: observations))

        #expect(rangeText.contains("结束"))
        #expect(abs(rangeRow.boundingBox.midY - custom.boundingBox.midY) < 0.035)
    }

    @Test("模型名称与模型分布标题左端对齐")
    @MainActor
    func modelNamesAlignWithCardTitle() throws {
        let observations = try recognizedText(
            in: render(
                TokenModelBreakdownChart(models: [
                    TokenHistoryModelSummary(
                        model: "Model Alpha",
                        totalTokens: 90_000_000,
                        estimatedCostUSD: 12
                    )
                ]),
                width: 800,
                height: 260
            )
        )
        let title = try #require(observation(containing: "模型分布", in: observations))
        let model = try #require(observation(containing: "Model Alpha", in: observations))

        #expect(abs(title.boundingBox.minX - model.boundingBox.minX) < 0.015)
    }

    @Test("模型条形紧跟最长模型名称且保持同一左端")
    @MainActor
    func modelBarsFollowLongestModelName() throws {
        let image = render(
            TokenModelBreakdownChart(models: [
                TokenHistoryModelSummary(
                    model: "GPT 5",
                    totalTokens: 90_000_000,
                    estimatedCostUSD: 12
                ),
                TokenHistoryModelSummary(
                    model: "codex-auto-review",
                    totalTokens: 45_000_000,
                    estimatedCostUSD: 6
                )
            ]),
            width: 800,
            height: 280
        )
        let observations = try recognizedText(in: image)
        let longestName = try #require(
            observation(containing: "codex-auto-review", in: observations)
        )
        let labelBottom = image.height
            - Int(longestName.boundingBox.maxY * Double(image.height))
        let labelTop = image.height
            - Int(longestName.boundingBox.minY * Double(image.height))
        let barStart = try #require(longestBlueRunStart(
            in: image,
            yRange: max(0, labelBottom - 4)..<min(image.height, labelTop + 4)
        ))
        let labelEnd = longestName.boundingBox.maxX * Double(image.width)

        #expect(Double(barStart) - labelEnd < 24)
    }

    @Test("模型分布高度随模型数量自然增长")
    @MainActor
    func modelBreakdownHeightTracksModelCount() {
        let compactHeight = modelBreakdownFittingHeight(modelCount: 2)
        let expandedHeight = modelBreakdownFittingHeight(modelCount: 8)

        #expect(compactHeight < expandedHeight)
        #expect(expandedHeight - compactHeight >= 150)
    }

    @Test("Token 活动和 Token 成本标题不显示箭头")
    @MainActor
    func tokenSectionHeadersDoNotShowChevrons() throws {
        let activityImage = render(
            TokenActivitySection(
                snapshot: nil,
                errorMessage: nil,
                isRefreshing: false,
                now: startDate,
                showHistory: {}
            ),
            width: 300,
            height: 120
        )
        let activityText = try recognizedText(in: activityImage)
        let activityTitle = try #require(
            observation(containing: "Token 活动", in: activityText)
        )
        let activityHeader = try #require(activityTitle.topCandidates(1).first?.string)
        #expect(!containsChevron(activityHeader))

        let costImage = render(
            TokenCostSection(
                snapshot: nil,
                errorMessage: nil,
                isRefreshing: false,
                isPresented: true,
                contentWillChange: {},
                contentDidChange: {},
                showHistory: {}
            ),
            width: 300,
            height: 120
        )
        let costText = try recognizedText(in: costImage)
        let costTitle = try #require(observation(containing: "Token 成本", in: costText))
        let costHeader = try #require(costTitle.topCandidates(1).first?.string)
        #expect(!containsChevron(costHeader))
    }

    @Test("趋势图为日期和右侧纵轴生成完整且统一的标签")
    func trendChartsProvideCompleteAxisLabels() {
        let dates = TokenHistoryChartAxisLabels.dateLabels(
            for: buckets,
            calendar: calendar,
            maximumCount: 5
        )
        let tokenTicks = TokenHistoryChartAxisLabels.tokenTicks(
            maximum: buckets.map(\.totalTokens).max() ?? 0
        )
        let costTicks = TokenHistoryChartAxisLabels.costTicks(
            maximum: buckets.map(\.estimatedCostUSD).max() ?? 0
        )

        #expect(dates.map(\.text) == ["7/9", "7/16", "7/24", "7/31", "8/7"])
        #expect(tokenTicks.map(\.text) == ["1.5亿", "1.0亿", "5000.0万", "0.0"])
        #expect(costTicks.map(\.text) == ["$20.00", "$15.00", "$10.00", "$5.00", "$0.00"])
    }

    @Test("右侧纵轴数值紧贴数据图表边缘")
    @MainActor
    func trailingAxisValuesAlignWithChartEdge() throws {
        let observations = try recognizedText(
            in: render(
                TokenCostHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: .constant(nil)
                ),
                width: 800,
                height: 270
            )
        )
        let topValue = try #require(observation(containing: "$20.00", in: observations))
        let finalDate = try #require(observation(containing: "8/7", in: observations))
        let gap = (topValue.boundingBox.minX - finalDate.boundingBox.maxX) * 800

        #expect(gap >= 4)
        #expect(gap <= 18)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var startDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 9))!
    }

    private var buckets: [TokenHistoryBucket] {
        (0..<30).map { index in
            let start = calendar.date(byAdding: .day, value: index, to: startDate)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return TokenHistoryBucket(
                interval: DateInterval(start: start, end: end),
                deviceTokens: Int64((index % 6 + 1) * 23_000_000),
                totalTokens: Int64((index % 6 + 1) * 23_000_000),
                recordedCostUSD: Double(index % 6 + 1) * 3.2,
                supplementTokens: 0,
                supplementCostUSD: 0,
                unpricedTokens: 0
            )
        }
    }

    @MainActor
    private func modelBreakdownFittingHeight(modelCount: Int) -> CGFloat {
        let models = (1...modelCount).map { index in
            TokenHistoryModelSummary(
                model: "model-\(index)",
                totalTokens: Int64(index * 1_000_000),
                estimatedCostUSD: Double(index)
            )
        }
        let host = NSHostingView(
            rootView: TokenModelBreakdownChart(models: models)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.colorScheme, .light)
        )
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 1)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        width: CGFloat,
        height: CGFloat
    ) -> CGImage {
        let host = NSHostingView(
            rootView: content
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .environment(\.colorScheme, .light)
                .background(Color.white)
        )
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()

        let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: representation)
        return representation.cgImage!
    }

    private func recognizedText(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    private func observation(
        containing text: String,
        in observations: [VNRecognizedTextObservation]
    ) -> VNRecognizedTextObservation? {
        observations.first { $0.topCandidates(1).first?.string.contains(text) == true }
    }

    private func longestBlueRunStart(in image: CGImage, yRange: Range<Int>) -> Int? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var bestStart: Int?
        var bestLength = 0
        for y in yRange {
            var runStart: Int?
            for x in 0..<image.width {
                let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                let isBlue = color.map {
                    $0.blueComponent > 0.75
                        && $0.redComponent < 0.4
                        && $0.greenComponent < 0.75
                } ?? false
                if isBlue {
                    runStart = runStart ?? x
                } else if let start = runStart {
                    if x - start > bestLength {
                        bestStart = start
                        bestLength = x - start
                    }
                    runStart = nil
                }
            }
        }
        return bestStart
    }

    private func containsChevron(_ text: String) -> Bool {
        [">", "〉", "›", "❯"].contains { text.contains($0) }
    }

    private func darkPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent < 0.3,
                   color.greenComponent < 0.3,
                   color.blueComponent < 0.3 {
                    count += 1
                }
            }
        }
        return count
    }
}
