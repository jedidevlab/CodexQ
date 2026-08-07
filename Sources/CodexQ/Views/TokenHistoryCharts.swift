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
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(
                            x: .value("时段", bucket.start),
                            y: .value("Token", bucket.totalTokens)
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
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let tokens = value.as(Int64.self) {
                                Text(TokenCountFormatter.compactNumber(tokens, fractionLength: 1))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedBucketStart)
                .chartKeyboardSelection(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                .frame(height: 210)
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
                Chart {
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
                .chartYAxis {
                    AxisMarks(format: Decimal.FormatStyle.Currency(code: "USD"))
                }
                .chartXSelection(value: $selectedBucketStart)
                .chartKeyboardSelection(
                    buckets: buckets,
                    selectedBucketStart: $selectedBucketStart
                )
                .frame(height: 210)
            }
        }
    }

    private var selectedBucket: TokenHistoryBucket? {
        selectedHistoryBucket(from: buckets, selectedStart: selectedBucketStart)
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
                Chart(sortedModels) { model in
                    BarMark(
                        x: .value(metric.rawValue, value(for: model)),
                        y: .value("模型", model.model)
                    )
                    .foregroundStyle(metric == .tokens ? Color.accentColor : .green)
                    .annotation(position: .trailing) {
                        Text(label(for: model))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(model.model)
                    .accessibilityValue(label(for: model))
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let modelName = value.as(String.self) {
                                Text(modelName)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(180, sortedModels.count * 30)))
            }
        }
    }

    private var compactedModels: [TokenHistoryModelSummary] {
        TokenHistoryModelCompactor.compact(models)
    }

    private var sortedModels: [TokenHistoryModelSummary] {
        compactedModels.sorted { value(for: $0) > value(for: $1) }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
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
