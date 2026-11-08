import AppKit
import SwiftUI
import Testing
@testable import CodexQ

@Suite("TokenHistoryRenderingTests", .serialized)
struct TokenHistoryRenderingTests {
    @Test("热力图使用适配背景的蓝色色阶")
    func heatmapPaletteBlendsWithBackdrop() {
        #expect((0...4).map {
            TokenActivityHeatmapPalette.hex(level: $0, colorScheme: .light)
        } == [0xBBC5CC, 0xA3CAEC, 0x70A9DA, 0x3F87C3, 0x255D95])
        #expect((0...4).map {
            TokenActivityHeatmapPalette.hex(level: $0, colorScheme: .dark)
        } == [0x404D59, 0x28557C, 0x347CB5, 0x5BA3D9, 0x97CAEF])
        #expect(TokenActivityHeatmapPalette.hex(level: nil, colorScheme: .light) == 0xBBC5CC)
        for scheme in [ColorScheme.light, .dark] {
            let opacities = (0...4).map {
                TokenActivityHeatmapPalette.opacity(level: $0, colorScheme: scheme)
            }
            #expect(opacities == opacities.sorted())
            #expect(opacities.allSatisfy { $0 >= 0.9 })
            #expect(opacities.last! < 1)
        }
    }

    @Test("浅蓝与无数据底格在浅色背景上仍有可辨色差")
    func lowUsageRemainsVisibleOverBackdrop() {
        func components(_ hex: UInt32) -> [Double] {
            [16, 8, 0].map { Double((hex >> $0) & 0xFF) }
        }
        let background = components(0xDCE4E5)
        let colors = (0...4).map { level in
            let rgb = components(TokenActivityHeatmapPalette.hex(level: level, colorScheme: .light))
            let alpha = TokenActivityHeatmapPalette.opacity(level: level, colorScheme: .light)
            return zip(rgb, background).map { $0 * alpha + $1 * (1 - alpha) }
        }
        func distance(_ lhs: [Double], _ rhs: [Double]) -> Double {
            zip(lhs, rhs).map { pow($0 - $1, 2) }.reduce(0, +).squareRoot()
        }
        #expect(distance(colors[0], background) > 35)
        for index in 1..<colors.count {
            #expect(distance(colors[index - 1], colors[index]) > 35)
        }
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
