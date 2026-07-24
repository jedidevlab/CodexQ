import AppKit
import Testing
@testable import CodexQ

struct QuotaBarLayoutTests {
    @Test("5 小时与周限额共用连续条尺寸")
    func quotaBarsUseSharedContinuousBarSize() {
        #expect(
            QuotaBarLayout.width
                == QuotaPopoverLayout.width - QuotaPopoverLayout.horizontalPadding * 2
        )
        #expect(QuotaBarLayout.height(for: .fiveHour) == 6)
    }

    @Test("5 小时与周限额条状高度一致")
    func quotaBarsUseSameHeight() {
        #expect(QuotaBarLayout.height(for: .fiveHour) == 6)
        #expect(QuotaBarLayout.height(for: .weekly) == QuotaBarLayout.height(for: .fiveHour))
    }

    @Test("5 小时与周限额总长度一致")
    func quotaBarsUseSameTotalLength() {
        #expect(QuotaBarLayout.width(for: .fiveHour) == 224)
        #expect(QuotaBarLayout.width(for: .weekly) == QuotaBarLayout.width(for: .fiveHour))
    }

    @Test("Pace 标记沿用 OpenUsage 的细刻度并上下突出")
    func paceMarkerMatchesOpenUsageDimensions() {
        #expect(QuotaBarLayout.markerWidth == 2)
        #expect(QuotaBarLayout.markerExtraHeight == 4)
    }

    @Test("额度条按显示百分比填充且 0% 不残留色块")
    func continuousFillMatchesRoundedDisplayPercentage() {
        #expect(QuotaBarLayout.fillWidth(percent: 84) == 224 * 0.84)
        #expect(QuotaBarLayout.fillWidth(percent: 84.4) == 224 * 0.84)
        #expect(QuotaBarLayout.fillWidth(percent: 0.4) == 0)
        #expect(QuotaBarLayout.fillWidth(percent: 0.6) == 6)
        #expect(QuotaBarLayout.fillWidth(percent: 1) == 6)
        #expect(QuotaBarLayout.fillWidth(percent: -10) == 0)
        #expect(QuotaBarLayout.fillWidth(percent: 120) == 224)
    }

    @Test("自适应活动视图使用紧凑弹窗宽度")
    func adaptiveActivityUsesCompactPopoverWidth() {
        #expect(QuotaPopoverLayout.width == 256)
    }

    @Test("额度行以三层结构铺满弹窗内容宽度")
    func quotaRowUsesFullWidthThreeTierLayout() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let rowStart = try #require(source.range(of: "private struct QuotaRow"))
        let rowEnd = try #require(source.range(of: "private struct ContinuousQuotaBar"))
        let rowSource = source[rowStart.lowerBound..<rowEnd.lowerBound]

        #expect(rowSource.contains("VStack(alignment: .leading, spacing: 4)"))
        #expect(rowSource.contains("HStack(alignment: .firstTextBaseline, spacing: 6)"))
        #expect(rowSource.contains("HStack(alignment: .firstTextBaseline, spacing: 8)"))
        #expect(rowSource.contains(".frame(width: QuotaBarLayout.width(for: period))"))
    }

    @Test("无限制额度显示完整灰色条状轨道")
    func unlimitedQuotaKeepsDisabledBar() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let rowStart = try #require(source.range(of: "private struct UnavailableQuotaRow"))
        let rowEnd = try #require(source.range(of: "private struct EmbeddedSettingsView"))
        let rowSource = source[rowStart.lowerBound..<rowEnd.lowerBound]

        #expect(rowSource.contains("Text(\"无限制\")"))
        #expect(rowSource.contains("DisabledContinuousQuotaBar"))
        #expect(rowSource.contains("Capsule()"))
        #expect(rowSource.contains(".fill(.quaternary)"))
    }

    @Test("右侧文案宽度不同不能改变进度条左边缘")
    func quotaRowsUseLeadingContainerAlignment() throws {
        let source = try String(
            contentsOfFile: "Sources/CodexQ/Views/QuotaPopoverView.swift",
            encoding: .utf8
        )
        let viewStart = try #require(source.range(of: "struct QuotaPopoverView"))
        let viewEnd = try #require(source.range(of: "private struct UnavailableQuotaRow"))
        let viewSource = source[viewStart.lowerBound..<viewEnd.lowerBound]

        #expect(viewSource.contains(
            "var body: some View {\n        VStack(alignment: .leading, spacing: 8) {"
        ))
    }
}
