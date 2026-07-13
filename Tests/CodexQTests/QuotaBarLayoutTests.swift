import AppKit
import Testing
@testable import CodexQ

struct QuotaBarLayoutTests {
    @Test("5 小时与周限额共用宽度块数和间距")
    func quotaBarsUseSharedWidthSegmentsAndSpacing() {
        #expect(QuotaBarLayout.width == 214)
        #expect(QuotaBarLayout.segments == 20)
        #expect(QuotaBarLayout.segmentSpacing == 1.5)
    }

    @Test("5 小时与周限额条块高度一致")
    func quotaBarsUseSameSegmentHeight() {
        #expect(QuotaBarLayout.height(for: .fiveHour) == 11)
        #expect(QuotaBarLayout.height(for: .weekly) == QuotaBarLayout.height(for: .fiveHour))
    }

    @Test("5 小时与周限额总长度一致")
    func quotaBarsUseSameTotalLength() {
        #expect(QuotaBarLayout.width(for: .fiveHour) == 214)
        #expect(QuotaBarLayout.width(for: .weekly) == QuotaBarLayout.width(for: .fiveHour))
    }

    @Test("未使用额度块需要清晰显示完整长度")
    func emptySegmentsRemainVisible() {
        #expect(QuotaBarLayout.emptySegmentOpacity >= 0.28)
    }

    @Test("进度标记高度不超过条块高度")
    func markerDoesNotExceedSegmentHeight() {
        #expect(QuotaBarLayout.markerExtraHeight == 0)
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
            "var body: some View {\n        VStack(alignment: .leading, spacing: 10) {"
        ))
    }
}
