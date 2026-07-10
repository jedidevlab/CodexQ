import SwiftUI

enum QuotaBarLayout {
    static let width: CGFloat = 214
    static let segments = 20
    static let segmentSpacing: CGFloat = 1.5
    static let cornerRadius: CGFloat = 1.5
    static let markerWidth: CGFloat = 5
    static let markerExtraHeight: CGFloat = 0
    static let emptySegmentOpacity = 0.28

    static func width(for period: QuotaPeriod) -> CGFloat {
        switch period {
        case .fiveHour, .weekly: return width
        }
    }

    static func height(for period: QuotaPeriod) -> CGFloat {
        switch period {
        case .fiveHour, .weekly: return 11
        }
    }
}

struct QuotaPopoverView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings: AppSettings
    let settingsDidChange: () -> Void
    @State private var relativeTimeNow = Date()
    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(spacing: 10) {
            if let snapshot = store.snapshot {
                QuotaRow(
                    title: "5 小时",
                    period: .fiveHour,
                    window: snapshot.fiveHour,
                    now: projectionNow,
                    resetText: formatter.string(
                        for: snapshot.fiveHour.resetsAt,
                        period: .fiveHour
                    )
                )
                QuotaRow(
                    title: "周限额",
                    period: .weekly,
                    window: snapshot.weekly,
                    now: projectionNow,
                    resetText: formatter.string(
                        for: snapshot.weekly.resetsAt,
                        period: .weekly
                    )
                )
            } else if store.isRefreshing {
                ProgressView("正在读取额度...")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let error = store.errorMessage {
                Text(RefreshFailureFormatter.summary(error))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .help(error)
            } else {
                Text("暂无额度数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            if let resetCredits = store.snapshot?.resetCredits {
                Divider()
                ResetCreditsSection(summary: resetCredits)
            }

            Divider()

            EmbeddedSettingsView(
                settings: settings,
                settingsDidChange: settingsDidChange
            )

            Divider()

            HStack {
                if let error = store.errorMessage, store.snapshot != nil {
                    Text(failureStatus(error: error))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(error)
                } else if let updatedAt = store.lastUpdatedAt {
                    Text(RelativeUpdateFormatter.string(
                        since: updatedAt,
                        now: relativeTimeNow
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("刷新")

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 316)
        .task(id: store.isPopoverPresented) {
            guard store.isPopoverPresented else { return }
            relativeTimeNow = Date()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                relativeTimeNow = Date()
            }
        }
    }

    private var projectionNow: Date {
        guard let lastUpdatedAt = store.lastUpdatedAt else {
            return relativeTimeNow
        }
        return max(relativeTimeNow, lastUpdatedAt)
    }

    private func failureStatus(error: String) -> String {
        RefreshFailureFormatter.status(
            error: error,
            updatedAt: store.lastUpdatedAt,
            now: relativeTimeNow
        )
    }
}

private struct EmbeddedSettingsView: View {
    @ObservedObject var settings: AppSettings
    let settingsDidChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("登录时启动", isOn: $settings.launchAtLogin)

            HStack(spacing: 8) {
                Toggle("额度预警通知", isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled {
                    Toggle("20%", isOn: $settings.notifyAt20)
                    Toggle("10%", isOn: $settings.notifyAt10)
                    Toggle("5%", isOn: $settings.notifyAt5)
                }
            }

        }
        .font(.caption)
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: settings.launchAtLogin) { _ in settingsDidChange() }
        .onChange(of: settings.notificationsEnabled) { _ in settingsDidChange() }
        .onChange(of: settings.notifyAt20) { _ in settingsDidChange() }
        .onChange(of: settings.notifyAt10) { _ in settingsDidChange() }
        .onChange(of: settings.notifyAt5) { _ in settingsDidChange() }
    }
}

private struct QuotaRow: View {
    let title: String
    let period: QuotaPeriod
    let window: QuotaWindow
    let now: Date
    let resetText: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let projection {
                        Text(paceText(for: projection))
                            .font(.caption)
                            .foregroundStyle(
                                projection.isInDeficit ? Color.red : Color.secondary
                            )
                    }
                }
                .frame(width: QuotaBarLayout.width(for: period))
                SegmentedBatteryBar(
                    period: period,
                    percent: window.remainingPercent,
                    markerPercent: projection.flatMap {
                        $0.isOnTrack ? nil : $0.expectedRemainingPercent
                    }
                )
                .help("红线表示按当前时间进度理论上应剩余的额度")
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var projection: QuotaProjection? {
        window.projection(at: now)
    }

    private func paceText(for projection: QuotaProjection) -> String {
        if projection.isOnTrack {
            return "进度正常"
        }
        let percent = Int(projection.displayPercent.rounded())
        if projection.isInDeficit, let eta = projection.etaSeconds {
            return "超额 \(percent)% · \(PaceFormatter.eta(eta))"
        }
        return projection.isInDeficit ? "进度超额 \(percent)%" : "进度余量 \(percent)%"
    }
}

private struct SegmentedBatteryBar: View {
    let period: QuotaPeriod
    let percent: Double
    let markerPercent: Double?

    var body: some View {
        let height = QuotaBarLayout.height(for: period)

        ZStack(alignment: .leading) {
            HStack(spacing: QuotaBarLayout.segmentSpacing) {
                ForEach(0..<QuotaBarLayout.segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: QuotaBarLayout.cornerRadius)
                        .fill(index < filledSegments ? barColor : Color.secondary.opacity(QuotaBarLayout.emptySegmentOpacity))
                }
            }

            if let markerPercent {
                Rectangle()
                    .fill(.red)
                    .frame(
                        width: QuotaBarLayout.markerWidth,
                        height: height + QuotaBarLayout.markerExtraHeight
                    )
                    .offset(x: markerOffset(for: markerPercent))
            }
        }
        .frame(width: QuotaBarLayout.width(for: period), height: height)
    }

    private var filledSegments: Int {
        Int(ceil(min(100, max(0, percent)) / (100 / Double(QuotaBarLayout.segments))))
    }

    private var barColor: Color {
        switch percent {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .green
        }
    }

    private func markerOffset(for percent: Double) -> CGFloat {
        let fraction = min(100, max(0, percent)) / 100
        let markerCenterOffset = QuotaBarLayout.markerWidth / 2
        return min(
            QuotaBarLayout.width(for: period) - QuotaBarLayout.markerWidth,
            max(0, QuotaBarLayout.width(for: period) * fraction - markerCenterOffset)
        )
    }
}
