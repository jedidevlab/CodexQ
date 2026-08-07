import AppKit
import Charts
import SwiftUI

struct TokenUsageHistoryChart: View {
    let buckets: [TokenHistoryBucket]
    @Binding var selectedBucketStart: Date?

    var body: some View {
        HistoryChartCard(title: "Token 趋势") {
            if buckets.allSatisfy({ $0.totalTokens == 0 }) {
                emptyState("所选范围暂无 Token 使用记录")
            } else {
                let dateLabels = TokenHistoryChartAxisLabels.dateLabels(for: buckets)
                let valueTicks = TokenHistoryChartAxisLabels.tokenTicks(
                    maximum: buckets.map(\.totalTokens).max() ?? 0
                )
                HistoryTrendChartLayout(dateLabels: dateLabels, valueTicks: valueTicks) {
                    Chart {
                        chartGridMarks(dateLabels: dateLabels, valueTicks: valueTicks)
                        ForEach(buckets) { bucket in
                            BarMark(
                                x: .value("时段", bucket.start),
                                y: .value("Token", Double(bucket.totalTokens))
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue("\(bucket.totalTokens) Token")
                        }
                        if buckets.count > 1 {
                            RuleMark(y: .value("平均", averageTokens))
                                .foregroundStyle(.secondary.opacity(0.55))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        if let bucket = selectedBucket {
                            RuleMark(x: .value("所选时段", bucket.start))
                                .foregroundStyle(.secondary)
                                .annotation(
                                    position: .top,
                                    alignment: .leading,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart), y: .fit(to: .chart)
                                    )
                                ) {
                                    TokenBucketTooltip(bucket: bucket, showsCost: false)
                                }
                        }
                    }
                    .chartXSelection(value: $selectedBucketStart)
                    .chartKeyboardSelection(
                        buckets: buckets,
                        selectedBucketStart: $selectedBucketStart
                    )
                }
            }
        }
    }

    private var averageTokens: Double {
        Double(buckets.reduce(Int64(0)) { $0 + $1.totalTokens }) / Double(max(1, buckets.count))
    }

    private var selectedBucket: TokenHistoryBucket? {
        selectedHistoryBucket(from: buckets, selectedStart: selectedBucketStart)
    }
}

struct TokenCostHistoryChart: View {
    let buckets: [TokenHistoryBucket]
    @Binding var selectedBucketStart: Date?

    var body: some View {
        HistoryChartCard(title: "估算成本趋势") {
            if buckets.allSatisfy({ $0.estimatedCostUSD == 0 }) {
                emptyState("所选范围暂无可计价成本")
            } else {
                let dateLabels = TokenHistoryChartAxisLabels.dateLabels(for: buckets)
                let valueTicks = TokenHistoryChartAxisLabels.costTicks(
                    maximum: buckets.map(\.estimatedCostUSD).max() ?? 0
                )
                HistoryTrendChartLayout(dateLabels: dateLabels, valueTicks: valueTicks) {
                    Chart {
                        chartGridMarks(dateLabels: dateLabels, valueTicks: valueTicks)
                        ForEach(buckets) { bucket in
                            AreaMark(
                                x: .value("时段", bucket.start),
                                y: .value("估算成本", bucket.estimatedCostUSD)
                            )
                            .foregroundStyle(Color.green.opacity(0.16))
                            LineMark(
                                x: .value("时段", bucket.start),
                                y: .value("估算成本", bucket.estimatedCostUSD)
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .accessibilityLabel(bucket.start.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue(String(format: "$%.2f", bucket.estimatedCostUSD))
                        }
                        if let bucket = selectedBucket {
                            RuleMark(x: .value("所选时段", bucket.start))
                                .foregroundStyle(.secondary)
                                .annotation(
                                    position: .top,
                                    alignment: .leading,
                                    overflowResolution: .init(
                                        x: .fit(to: .chart), y: .fit(to: .chart)
                                    )
                                ) {
                                    TokenBucketTooltip(bucket: bucket, showsCost: true)
                                }
                            PointMark(
                                x: .value("所选时段", bucket.start),
                                y: .value("估算成本", bucket.estimatedCostUSD)
                            )
                            .foregroundStyle(.green)
                        }
                    }
                    .chartXSelection(value: $selectedBucketStart)
                    .chartKeyboardSelection(
                        buckets: buckets,
                        selectedBucketStart: $selectedBucketStart
                    )
                }
            }
        }
    }

    private var selectedBucket: TokenHistoryBucket? {
        selectedHistoryBucket(from: buckets, selectedStart: selectedBucketStart)
    }
}

struct TokenHistoryChartDateLabel: Identifiable, Equatable {
    let date: Date
    let text: String

    var id: Date { date }
}

struct TokenHistoryChartValueTick: Identifiable, Equatable {
    let value: Double
    let text: String

    var id: Double { value }
}

enum TokenHistoryChartAxisLabels {
    static func dateLabels(
        for buckets: [TokenHistoryBucket],
        calendar: Calendar = .current,
        maximumCount: Int = 5
    ) -> [TokenHistoryChartDateLabel] {
        guard !buckets.isEmpty, maximumCount > 0 else { return [] }
        let count = min(maximumCount, buckets.count)
        let indices: [Int]
        if count == 1 {
            indices = [0]
        } else {
            indices = (0..<count).map { position in
                Int((Double(position) * Double(buckets.count - 1) / Double(count - 1)).rounded())
            }
        }
        return indices.map { index in
            let bucket = buckets[index]
            return TokenHistoryChartDateLabel(
                date: bucket.start,
                text: dateText(for: bucket, calendar: calendar)
            )
        }
    }

    static func tokenTicks(maximum: Int64) -> [TokenHistoryChartValueTick] {
        ticks(maximum: Double(maximum)) { value in
            TokenCountFormatter.compactNumber(Int64(value.rounded()), fractionLength: 1)
        }
    }

    static func costTicks(maximum: Double) -> [TokenHistoryChartValueTick] {
        ticks(maximum: maximum) { String(format: "$%.2f", $0) }
    }

    private static func dateText(
        for bucket: TokenHistoryBucket,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: bucket.start)
        if bucket.interval.duration >= 300 * 24 * 60 * 60 {
            return components.year.map(String.init) ?? ""
        }
        if bucket.interval.duration >= 27 * 24 * 60 * 60 {
            return components.month.map { "\($0)月" } ?? ""
        }
        guard let month = components.month, let day = components.day else { return "" }
        return "\(month)/\(day)"
    }

    private static func ticks(
        maximum: Double,
        formatter: (Double) -> String
    ) -> [TokenHistoryChartValueTick] {
        guard maximum > 0 else {
            return [TokenHistoryChartValueTick(value: 0, text: formatter(0))]
        }
        let step = niceStep(maximum / 4)
        let upperBound = ceil(maximum / step) * step
        return stride(from: upperBound, through: 0, by: -step).map {
            TokenHistoryChartValueTick(value: $0, text: formatter($0))
        }
    }

    private static func niceStep(_ value: Double) -> Double {
        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude
        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 2.5 {
            multiplier = 2.5
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        return multiplier * magnitude
    }
}

private struct HistoryTrendChartLayout<ChartView: View>: View {
    let dateLabels: [TokenHistoryChartDateLabel]
    let valueTicks: [TokenHistoryChartValueTick]
    @ViewBuilder let chart: ChartView

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                chart
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...(valueTicks.first?.value ?? 1))
                    .frame(height: 188)
                HStack(spacing: 0) {
                    ForEach(Array(dateLabels.enumerated()), id: \.element.id) { index, label in
                        Text(label.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                        if index < dateLabels.count - 1 {
                            Spacer(minLength: 8)
                        }
                    }
                }
                .frame(height: 18)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(valueTicks.enumerated()), id: \.element.id) { index, tick in
                    Text(tick.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if index < valueTicks.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 72, height: 188)
        }
        .frame(height: 210)
    }
}

@ChartContentBuilder
private func chartGridMarks(
    dateLabels: [TokenHistoryChartDateLabel],
    valueTicks: [TokenHistoryChartValueTick]
) -> some ChartContent {
    ForEach(valueTicks) { tick in
        RuleMark(y: .value("纵轴刻度", tick.value))
            .foregroundStyle(.secondary.opacity(0.16))
    }
    ForEach(dateLabels) { label in
        RuleMark(x: .value("日期刻度", label.date))
            .foregroundStyle(.secondary.opacity(0.18))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}

struct ResponsiveTokenHistoryCharts: View {
    let buckets: [TokenHistoryBucket]
    @Binding var selectedBucketStart: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                TokenUsageHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                .frame(maxWidth: .infinity)
                TokenCostHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 900)

            VStack(alignment: .leading, spacing: 16) {
                TokenUsageHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                TokenCostHistoryChart(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
            }
        }
    }
}

struct TokenModelBreakdownChart: View {
    enum Metric: String, CaseIterable, Identifiable {
        case tokens = "Token"
        case cost = "成本"
        var id: Self { self }
    }

    let models: [TokenHistoryModelSummary]
    @State private var metric: Metric = .tokens

    var body: some View {
        HistoryChartCard(title: "模型分布") {
            Picker("指标", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            if compactedModels.isEmpty {
                emptyState("所选范围暂无模型记录")
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedModels) { model in
                        TokenModelBreakdownRow(
                            model: model,
                            value: value(for: model),
                            maximumValue: maximumValue,
                            valueLabel: label(for: model),
                            labelColumnWidth: modelLabelWidth,
                            color: metric == .tokens ? .accentColor : .green
                        )
                    }
                }
                .frame(minHeight: 180, alignment: .top)
            }
        }
    }

    private var compactedModels: [TokenHistoryModelSummary] {
        TokenHistoryModelCompactor.compact(models)
    }

    private var sortedModels: [TokenHistoryModelSummary] {
        compactedModels.sorted { value(for: $0) > value(for: $1) }
    }

    private var maximumValue: Double {
        sortedModels.map(value(for:)).max() ?? 0
    }

    private var modelLabelWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let width = sortedModels.map {
            ($0.model as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return min(180, ceil(width))
    }

    private func value(for model: TokenHistoryModelSummary) -> Double {
        switch metric {
        case .tokens: return Double(model.totalTokens)
        case .cost: return model.estimatedCostUSD ?? 0
        }
    }

    private func label(for model: TokenHistoryModelSummary) -> String {
        switch metric {
        case .tokens:
            return TokenCountFormatter.compactNumber(model.totalTokens, fractionLength: 1)
        case .cost:
            return model.estimatedCostUSD.map { String(format: "$%.2f", $0) } ?? "未计价"
        }
    }
}

struct TokenModelBreakdownRow: View {
    let model: TokenHistoryModelSummary
    let value: Double
    let maximumValue: Double
    let valueLabel: String
    let labelColumnWidth: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(model.model)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: labelColumnWidth, alignment: .leading)
                .help(model.model)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: barWidth(in: geometry.size.width))
                }
            }
            .frame(height: 18)

            Text(valueLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.model)，\(valueLabel)")
    }

    private func barWidth(in availableWidth: CGFloat) -> CGFloat {
        guard value > 0, maximumValue > 0 else { return 0 }
        return max(2, availableWidth * value / maximumValue)
    }
}

enum TokenHistoryModelCompactor {
    static func compact(
        _ models: [TokenHistoryModelSummary],
        namedLimit: Int = 8
    ) -> [TokenHistoryModelSummary] {
        guard models.count > namedLimit else { return models }
        let sorted = models.sorted {
            if $0.totalTokens == $1.totalTokens { return $0.model < $1.model }
            return $0.totalTokens > $1.totalTokens
        }
        let named = Array(sorted.prefix(namedLimit))
        let remainder = sorted.dropFirst(namedLimit)
        let costValues = remainder.compactMap(\.estimatedCostUSD)
        let other = TokenHistoryModelSummary(
            model: "其他",
            totalTokens: remainder.reduce(Int64(0)) { $0 + $1.totalTokens },
            estimatedCostUSD: costValues.isEmpty ? nil : costValues.reduce(0, +)
        )
        return named + [other]
    }
}

private struct HistoryChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            TokenHistoryCardSurface(cornerRadius: 12)
        }
    }
}

private struct TokenBucketTooltip: View {
    let bucket: TokenHistoryBucket
    let showsCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bucket.start.formatted(date: .abbreviated, time: .omitted))
                .fontWeight(.semibold)
            Text("Token：\(TokenCountFormatter.compactNumber(bucket.totalTokens))")
            Text("设备记录：\(TokenCountFormatter.compactNumber(bucket.deviceTokens))")
            if bucket.supplementTokens > 0 {
                Text("官方差额：\(TokenCountFormatter.compactNumber(bucket.supplementTokens))")
            }
            if showsCost {
                Text(String(format: "记录成本：$%.2f", bucket.recordedCostUSD))
                Text(String(format: "差额估算：$%.2f", bucket.supplementCostUSD))
                Text(String(format: "估算成本：$%.2f", bucket.estimatedCostUSD))
            }
            if bucket.unpricedTokens > 0 {
                Text("另有 \(TokenCountFormatter.compactNumber(bucket.unpricedTokens)) Token 未计价")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func chartKeyboardSelection(
        buckets: [TokenHistoryBucket],
        selectedBucketStart: Binding<Date?>
    ) -> some View {
        focusable()
            .onKeyPress(.leftArrow) {
                moveSelection(by: -1, buckets: buckets, selection: selectedBucketStart)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveSelection(by: 1, buckets: buckets, selection: selectedBucketStart)
                return .handled
            }
            .onKeyPress(.escape) {
                selectedBucketStart.wrappedValue = nil
                return .handled
            }
    }
}

private func moveSelection(
    by offset: Int,
    buckets: [TokenHistoryBucket],
    selection: Binding<Date?>
) {
    guard !buckets.isEmpty else { return }
    let currentIndex = selection.wrappedValue.flatMap { selected in
        buckets.indices.min { first, second in
            abs(buckets[first].start.timeIntervalSince(selected))
                < abs(buckets[second].start.timeIntervalSince(selected))
        }
    } ?? (offset > 0 ? -1 : buckets.count)
    selection.wrappedValue = buckets[min(max(currentIndex + offset, 0), buckets.count - 1)].start
}

private func selectedHistoryBucket(
    from buckets: [TokenHistoryBucket],
    selectedStart: Date?
) -> TokenHistoryBucket? {
    guard let selectedStart else { return nil }
    return buckets.min {
        abs($0.start.timeIntervalSince(selectedStart))
            < abs($1.start.timeIntervalSince(selectedStart))
    }
}

@ViewBuilder
private func emptyState(_ message: String) -> some View {
    Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
}
