import AppKit
import SwiftUI
import Testing
@testable import CodexQ

@Suite("TokenHistoryRenderingTests", .serialized)
struct TokenHistoryRenderingTests {
    @Test("热力图浅色与深色五级颜色和 ChatGPT 一致")
    func heatmapPaletteMatchesChatGPT() {
        #expect((0...4).map {
            TokenActivityHeatmapPalette.hex(level: $0, colorScheme: .light)
        } == [0xF3F3F3, 0xCCE6FF, 0x66B5FF, 0x0285FF, 0x004F99])
        #expect((0...4).map {
            TokenActivityHeatmapPalette.hex(level: $0, colorScheme: .dark)
        } == [0x303030, 0x013566, 0x004F99, 0x0285FF, 0x66B5FF])
        #expect(TokenActivityHeatmapPalette.hex(level: nil, colorScheme: .light) == 0xF3F3F3)
    }

    @Test("历史入口标题悬浮时使用可点击指针")
    @MainActor
    func historyNavigationTitleUsesPointingHandCursor() {
        NSCursor.arrow.set()
        defer { TokenHistoryNavigationCursor.update(isHovered: false) }

        TokenHistoryNavigationCursor.update(isHovered: true)

        #expect(NSCursor.current == NSCursor.pointingHand)
    }

    @Test("Token 趋势图生成日期与数量刻度")
    func tokenTrendProvidesAxisLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let starts = [9, 16, 24, 31].compactMap {
            calendar.date(from: DateComponents(year: 2026, month: 7, day: $0))
        } + [calendar.date(from: DateComponents(year: 2026, month: 8, day: 7))!]
        let buckets = starts.map {
            TokenHistoryBucket(
                interval: DateInterval(start: $0, duration: 86_400),
                deviceTokens: 0,
                totalTokens: 150_000_000,
                recordedCostUSD: 0,
                supplementTokens: 150_000_000,
                supplementCostUSD: 0,
                unpricedTokens: 0
            )
        }

        #expect(TokenHistoryChartAxisLabels.dateLabels(
            for: buckets,
            calendar: calendar,
            maximumCount: 5
        ).map(\.text) == ["7/9", "7/16", "7/24", "7/31", "8/7"])
        #expect(TokenHistoryChartAxisLabels.tokenTicks(maximum: 150_000_000).map(\.text) == [
            "1.5亿", "1.0亿", "5000.0万", "0.0"
        ])
    }
}
