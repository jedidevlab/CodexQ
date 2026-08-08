import SwiftUI

struct TokenHistoryView: View {
    @ObservedObject var store: TokenHistoryStore
    @State private var selectedBucketStart: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = store.snapshot {
                summaryStrip(snapshot.summary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ResponsiveTokenHistoryCharts(
                            buckets: snapshot.buckets,
                            selectedBucketStart: $selectedBucketStart
                        )
                        TokenModelBreakdownChart(models: snapshot.models)
                        footerNotes(snapshot)
                    }
                    .padding(.bottom, 12)
                }
            } else if store.isLoading {
                ProgressView("正在读取 Token 历史...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.errorMessage {
                ContentUnavailableView {
                    Label("历史数据暂不可用", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试", action: store.reload)
                }
            } else {
                ContentUnavailableView("暂无历史数据", systemImage: "chart.xyaxis.line")
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .task(id: store.selectionIdentity) {
            selectedBucketStart = nil
            store.loadIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            rangeRow
        }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Token 使用与成本")
                .font(.largeTitle.weight(.bold))
            Text("API 价格估算，非实际订阅账单")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if store.isLoading, store.snapshot != nil {
                ProgressView().controlSize(.small)
            }
            Button(action: store.reload) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("刷新历史数据")
        }
    }

    private var rangeRow: some View {
        HStack(spacing: 12) {
            Label("日期", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("范围", selection: $store.mode) {
                ForEach(TokenHistoryRangeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 320, maxWidth: 440)
            contextualControls
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var contextualControls: some View {
        switch store.mode {
        case .day:
            DatePicker("所在周", selection: $store.selectedDay, displayedComponents: .date)
                .datePickerStyle(.compact)
        case .month:
            Picker("年份", selection: $store.selectedYear) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .frame(width: 100)
            Picker("月份", selection: $store.selectedMonth) {
                ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
            }
            .frame(minWidth: 110)
        case .year:
            Picker("年份", selection: $store.selectedYear) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .frame(width: 110)
        case .subscription:
            if store.availableSubscriptionCycles.isEmpty {
                Text("暂无可用订阅周期")
                    .foregroundStyle(.secondary)
            } else {
                Picker("订阅周期", selection: $store.selectedSubscriptionInterval) {
                    ForEach(store.availableSubscriptionCycles) { cycle in
                        Text(cycleLabel(cycle)).tag(Optional(cycle.interval))
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        case .cumulative:
            EmptyView()
        case .custom:
            DatePicker("开始", selection: $store.customStart, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker("结束", selection: $store.customEnd, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }

    private func summaryStrip(_ summary: TokenHistorySummary) -> some View {
        HStack(spacing: 10) {
            HistorySummaryCard(
                title: "Token 总量",
                value: TokenCountFormatter.compactNumber(summary.totalTokens, fractionLength: 1),
                accent: .blue
            )
            HistorySummaryCard(
                title: "估算成本",
                value: currency(summary.estimatedCostUSD),
                accent: .green
            )
            HistorySummaryCard(
                title: "日均 Token",
                value: TokenCountFormatter.compactNumber(
                    Int64(summary.averageDailyTokens.rounded()),
                    fractionLength: 1
                ),
                accent: .indigo
            )
            HistorySummaryCard(
                title: "日均成本",
                value: currency(summary.averageDailyCostUSD),
                accent: .orange
            )
        }
    }

    private func footerNotes(_ snapshot: TokenHistorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            qualityRow(snapshot)
            if snapshot.summary.unpricedTokens > 0 {
                Text("未计价 Token：\(TokenCountFormatter.compactNumber(snapshot.summary.unpricedTokens))。这部分 Token 缺少对应 API 价格，会计入 Token 总量，但不计入估算成本。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func qualityRow(_ snapshot: TokenHistorySnapshot) -> some View {
        HStack(spacing: 8) {
            Label(scopeLabel(snapshot.coverage.dataScope), systemImage: "externaldrive")
            Text("官方活动覆盖 \(snapshot.coverage.activityDaysAvailable)/\(snapshot.coverage.calendarDaysInRange) 天")
            if snapshot.coverage.skippedSessionFileCount > 0 {
                Text("跳过 \(snapshot.coverage.skippedSessionFileCount) 个会话文件")
            }
            if let message = snapshot.coverage.syncMessage {
                Text(message)
            }
            if let warning = snapshot.warningMessage {
                Text(warning).foregroundStyle(.orange)
            }
            if let error = store.errorMessage {
                Text("刷新失败：\(error)").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 10)...current).reversed()
    }

    private func cycleLabel(_ cycle: SubscriptionCycle) -> String {
        let range = "\(cycle.interval.start.formatted(.dateTime.month().day()))–\(cycle.interval.end.formatted(.dateTime.month().day()))"
        if cycle.isCurrent { return "当前 · \(range)" }
        return cycle.isInferred ? "\(range) · 按当前续费日推算" : range
    }

    private func scopeLabel(_ scope: TokenCostDataScope) -> String {
        switch scope {
        case .local: return "本机成本记录"
        case .singleDevice: return "单设备账本"
        case .multiDevice(let count): return "\(count) 台设备账本"
        case .syncDelayed: return "同步延迟，显示缓存"
        case .syncBlocked: return "同步受阻，显示本机"
        case .partial(let count): return "\(count) 台设备，部分数据"
        }
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

struct TokenHistoryCardSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
    }
}

private struct HistorySummaryCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            TokenHistoryCardSurface(cornerRadius: 12)
        }
    }
}
