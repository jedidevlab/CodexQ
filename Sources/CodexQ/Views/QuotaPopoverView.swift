import AppKit
import SwiftUI

enum QuotaBarLayout {
    static let width: CGFloat = 214
    static let markerWidth: CGFloat = 2
    static let markerExtraHeight: CGFloat = 4

    static func fillWidth(percent: Double) -> CGFloat {
        let fraction = min(100, max(0, percent)) / 100
        guard fraction > 0 else { return 0 }
        return max(height(for: .fiveHour), width * CGFloat(fraction))
    }

    static func width(for period: QuotaPeriod) -> CGFloat {
        switch period {
        case .fiveHour, .weekly: return width
        }
    }

    static func height(for period: QuotaPeriod) -> CGFloat {
        switch period {
        case .fiveHour, .weekly: return 7
        }
    }
}

struct QuotaPopoverView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings: AppSettings
    let contentDidChange: () -> Void
    let interactionDidChange: (PopoverInteraction, Bool) -> Void
    @State private var relativeTimeNow = Date()
    @State private var isResetCreditsExpanded = false
    @State private var isSettingsExpanded = false
    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = store.snapshot {
                if let fiveHour = snapshot.fiveHour {
                    QuotaRow(
                        title: "5 小时",
                        period: .fiveHour,
                        window: fiveHour,
                        now: projectionNow,
                        resetText: formatter.string(
                            for: fiveHour.resetsAt,
                            period: .fiveHour
                        )
                    )
                } else {
                    UnavailableQuotaRow()
                }
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

            Divider()

            TokenActivitySection(
                snapshot: store.tokenActivity,
                errorMessage: store.tokenActivityErrorMessage,
                isRefreshing: store.isTokenActivityRefreshing,
                now: relativeTimeNow
            )

            if let resetCredits = store.snapshot?.resetCredits {
                Divider()
                ResetCreditsSection(
                    summary: resetCredits,
                    isExpanded: $isResetCreditsExpanded
                )
            }

            if isSettingsExpanded {
                Divider()
                EmbeddedSettingsView(
                    settings: settings,
                    settingsDidChange: contentDidChange
                )
            }

            Divider()

            HStack(spacing: 8) {
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
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .monospacedDigit()
                }
                Spacer()
                Button {
                    isSettingsExpanded.toggle()
                } label: {
                    FooterIconButtonLabel(
                        systemName: isSettingsExpanded ? "gearshape.fill" : "gearshape"
                    )
                }
                .buttonStyle(.borderless)
                .help("设置")
                .accessibilityLabel("设置")

                Button {
                    Task { await store.refreshFromButton() }
                } label: {
                    if store.isRefreshButtonBusy {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 24, height: 24)
                    } else {
                        FooterIconButtonLabel(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isAnyRefreshing)
                .help("立即刷新")
                .accessibilityLabel("立即刷新")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    FooterIconButtonLabel(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出")
                .accessibilityLabel("退出")
            }
        }
        .padding(16)
        .frame(width: 316)
        .onHover { isHovering in
            interactionDidChange(.pointer, isHovering)
        }
        .onChange(of: isResetCreditsExpanded) { _, isExpanded in
            interactionDidChange(.resetCredits, isExpanded)
            contentDidChange()
        }
        .onChange(of: isSettingsExpanded) { _, isExpanded in
            interactionDidChange(.settings, isSettingsExpanded)
            contentDidChange()
        }
        .onChange(of: store.isPopoverPresented) { _, isPresented in
            guard !isPresented else { return }
            isResetCreditsExpanded = false
            isSettingsExpanded = false
        }
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

    private var isAnyRefreshing: Bool {
        store.isRefreshing || store.isTokenActivityRefreshing
    }

    private func failureStatus(error: String) -> String {
        RefreshFailureFormatter.status(
            error: error,
            updatedAt: store.lastUpdatedAt,
            now: relativeTimeNow
        )
    }
}

private struct FooterIconButtonLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

private struct UnavailableQuotaRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("5 小时")
                    .font(.headline)
                Spacer()
                Text("无限制")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
            DisabledContinuousQuotaBar(period: .fiveHour)
        }
    }
}

private struct DisabledContinuousQuotaBar: View {
    let period: QuotaPeriod

    var body: some View {
        Capsule().fill(.quaternary)
            .frame(
                width: QuotaBarLayout.width(for: period),
                height: QuotaBarLayout.height(for: period)
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
        .onChange(of: settings.launchAtLogin) { settingsDidChange() }
        .onChange(of: settings.notificationsEnabled) { _, requestedEnabled in
            settingsDidChange()
            guard requestedEnabled else { return }
            Task {
                let granted = await QuotaNotificationService().requestAuthorization()
                settings.notificationsEnabled = NotificationAuthorizationPolicy.effectiveEnabled(
                    requestedEnabled: settings.notificationsEnabled,
                    authorizationGranted: granted
                )
            }
        }
        .onChange(of: settings.notifyAt20) { settingsDidChange() }
        .onChange(of: settings.notifyAt10) { settingsDidChange() }
        .onChange(of: settings.notifyAt5) { settingsDidChange() }
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
                    if let projection,
                       let paceText = PaceFormatter.status(projection) {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .systemRed))
                            Text(paceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: QuotaBarLayout.width(for: period))
                ContinuousQuotaBar(
                    period: period,
                    percent: window.remainingPercent,
                    markerPercent: projection.flatMap {
                        $0.isOnTrack ? nil : $0.expectedRemainingPercent
                    }
                )
                .help("刻度表示按当前时间进度理论上应剩余的额度")
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(resetText)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var projection: QuotaProjection? {
        window.projection(at: now)
    }

}

private struct ContinuousQuotaBar: View {
    let period: QuotaPeriod
    let percent: Double
    let markerPercent: Double?

    var body: some View {
        let height = QuotaBarLayout.height(for: period)

        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)

            Capsule()
                .fill(barColor)
                .frame(width: QuotaBarLayout.fillWidth(percent: percent))
        }
        .frame(width: QuotaBarLayout.width(for: period), height: height)
        .overlay(alignment: .leading) {
            if let markerPercent {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.55))
                    .frame(
                        width: QuotaBarLayout.markerWidth,
                        height: height + QuotaBarLayout.markerExtraHeight
                    )
                    .offset(x: markerOffset(for: markerPercent))
            }
        }
    }

    private var barColor: Color {
        switch percent {
        case 0..<20: return Color(nsColor: .systemRed)
        case 20..<50: return Color(nsColor: .systemYellow)
        default: return Color(nsColor: .systemBlue)
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
