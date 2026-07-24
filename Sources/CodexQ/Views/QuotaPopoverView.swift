import AppKit
import SwiftUI

enum QuotaPopoverLayout {
    static let width: CGFloat = 256
    static let horizontalPadding: CGFloat = 16
}

enum QuotaBarLayout {
    static let width = QuotaPopoverLayout.width - QuotaPopoverLayout.horizontalPadding * 2
    static let markerWidth: CGFloat = 2
    static let markerExtraHeight: CGFloat = 4

    static func fillWidth(percent: Double) -> CGFloat {
        let fraction = min(100, max(0, percent)).rounded() / 100
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
        case .fiveHour, .weekly: return 6
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
    @AppStorage("quotaResetDisplayMode") private var resetDisplayModeRawValue = ResetDisplayMode.relative.rawValue
    private let formatter = ResetTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = store.snapshot {
                if let planName = PlanTypeFormatter.displayName(for: snapshot.planType) {
                    VStack(spacing: 5) {
                        PlanHeader(planName: planName)
                        InsetSeparator()
                    }
                }
                if let fiveHour = snapshot.fiveHour {
                    QuotaRow(
                        title: "5 小时",
                        period: .fiveHour,
                        window: fiveHour,
                        now: projectionNow,
                        resetDisplayMode: resetDisplayMode,
                        formatter: formatter,
                        toggleResetDisplay: toggleResetDisplay
                    )
                } else {
                    UnavailableQuotaRow()
                }
                QuotaRow(
                    title: "周限额",
                    period: .weekly,
                    window: snapshot.weekly,
                    now: projectionNow,
                    resetDisplayMode: resetDisplayMode,
                    formatter: formatter,
                    toggleResetDisplay: toggleResetDisplay
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

            InsetSeparator()

            TokenActivitySection(
                snapshot: store.tokenActivity,
                errorMessage: store.tokenActivityErrorMessage,
                isRefreshing: store.isTokenActivityRefreshing,
                now: relativeTimeNow
            )

            InsetSeparator()

            TokenCostSection(
                snapshot: store.tokenCost,
                errorMessage: store.tokenCostErrorMessage,
                isRefreshing: store.isTokenActivityRefreshing,
                isPresented: store.isPopoverPresented,
                contentDidChange: contentDidChange
            )

            if let resetCredits = store.snapshot?.resetCredits {
                InsetSeparator()
                ResetCreditsSection(
                    summary: resetCredits,
                    isExpanded: $isResetCreditsExpanded
                )
            }

            if isSettingsExpanded {
                InsetSeparator()
                EmbeddedSettingsView(
                    settings: settings,
                    costDataScope: store.tokenCost?.dataScope ?? .local,
                    costSyncMessage: store.tokenCost?.syncMessage,
                    settingsDidChange: contentDidChange,
                    costSyncDidChange: {
                        Task { await store.refreshFromButton() }
                    }
                )
            }

            VStack(spacing: 4) {
                InsetSeparator()

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
        }
        .padding(.horizontal, QuotaPopoverLayout.horizontalPadding)
        .padding(.top, QuotaPopoverLayout.horizontalPadding)
        .padding(.bottom, 10)
        .frame(width: QuotaPopoverLayout.width)
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
                try? await Task.sleep(for: .seconds(30))
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

    private var resetDisplayMode: ResetDisplayMode {
        ResetDisplayMode(rawValue: resetDisplayModeRawValue) ?? .relative
    }

    private func toggleResetDisplay() {
        resetDisplayModeRawValue = resetDisplayMode.opposite.rawValue
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

private struct PlanHeader: View {
    let planName: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Codex")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            PlanBadge(planName: planName)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlanBadge: View {
    let planName: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Text(planName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(.thinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .accessibilityLabel("套餐 \(planName)")
    }
}

struct InsetSeparator: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.035),
                    Color.primary.opacity(0.08),
                    Color.primary.opacity(0.035)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor).opacity(0.16),
                    Color(nsColor: .textBackgroundColor).opacity(0.35),
                    Color(nsColor: .textBackgroundColor).opacity(0.16)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .offset(y: 1)
        }
        .frame(height: 2)
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
    let costDataScope: TokenCostDataScope
    let costSyncMessage: String?
    let settingsDidChange: () -> Void
    let costSyncDidChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("登录时启动", isOn: $settings.launchAtLogin)

            HStack(spacing: 4) {
                Toggle("额度预警通知", isOn: $settings.notificationsEnabled)
                if settings.notificationsEnabled {
                    Toggle("20%", isOn: $settings.notifyAt20)
                    Toggle("10%", isOn: $settings.notifyAt10)
                    Toggle("5%", isOn: $settings.notifyAt5)
                }
            }

            if settings.notificationsEnabled,
               let warning = settings.notificationPermissionWarning {
                Text(warning)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Toggle("iCloud 同步", isOn: costSyncBinding)
                Spacer(minLength: 4)
                if settings.icloudCostSyncEnabled {
                    Button("更换文件夹…") {
                        chooseCostSyncFolder()
                    }
                    .buttonStyle(.borderless)
                }
            }

            CostSyncImpactCard(
                isEnabled: settings.icloudCostSyncEnabled,
                dataScope: costDataScope,
                message: settings.icloudCostSyncEnabled
                    ? costSyncMessage ?? settings.icloudCostSyncSetupError
                    : settings.icloudCostSyncSetupError
            )
        }
        .font(.caption)
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: settings.launchAtLogin) { settingsDidChange() }
        .onChange(of: settings.notificationsEnabled) { _, requestedEnabled in
            settingsDidChange()
            guard requestedEnabled else {
                settings.updateNotificationPermissionWarning(authorizationGranted: true)
                return
            }
            Task {
                let granted = await QuotaNotificationService().requestAuthorizationIfNeeded()
                settings.updateNotificationPermissionWarning(authorizationGranted: granted)
            }
        }
        .onChange(of: settings.notifyAt20) { settingsDidChange() }
        .onChange(of: settings.notifyAt10) { settingsDidChange() }
        .onChange(of: settings.notifyAt5) { settingsDidChange() }
    }

    private var costSyncBinding: Binding<Bool> {
        Binding(
            get: { settings.icloudCostSyncEnabled },
            set: { isEnabled in
                if isEnabled {
                    chooseCostSyncFolder()
                } else {
                    settings.disableICloudCostSync()
                    settingsDidChange()
                    costSyncDidChange()
                }
            }
        )
    }

    private func chooseCostSyncFolder() {
        guard let folderURL = ICloudDriveFolderPicker.chooseFolder() else { return }
        Task {
            do {
                try await settings.enableICloudCostSync(folderURL: folderURL)
                settingsDidChange()
                costSyncDidChange()
            } catch {
                settingsDidChange()
            }
        }
    }
}

private struct CostSyncImpactCard: View {
    let isEnabled: Bool
    let dataScope: TokenCostDataScope
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(impactSummary)
                .fixedSize(horizontal: false, vertical: true)
            Text("仅同步模型、时间和 Token 数；不含会话内容和登录信息。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(isDelayed ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var isDelayed: Bool {
        switch dataScope {
        case .syncDelayed, .syncBlocked: return true
        case .local, .singleDevice, .multiDevice, .partial: return false
        }
    }

    private var impactSummary: String {
        guard isEnabled else {
            return "未开启：Token 活动不受影响；Token 成本仅统计本机。"
        }
        if case .syncBlocked = dataScope {
            return "已开启：Token 活动不受影响；同步暂停，Token 成本暂时仅统计本机。"
        }
        return isDelayed
            ? "已开启：Token 活动不受影响；Token 成本暂用本机与上次同步数据。"
            : "已开启：Token 活动不受影响；Token 成本汇总多台 Mac。"
    }
}

private struct QuotaRow: View {
    let title: String
    let period: QuotaPeriod
    let window: QuotaWindow
    let now: Date
    let resetDisplayMode: ResetDisplayMode
    let formatter: ResetTimeFormatter
    let toggleResetDisplay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                paceWarning
            }

            ContinuousQuotaBar(
                period: period,
                percent: window.remainingPercent,
                markerPercent: paceState.markerPercent,
                severity: paceState.severity
            )
            .help(paceTooltip)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int(window.remainingPercent.rounded()))% 剩余")
                    .font(.caption)
                    .monospacedDigit()

                Spacer(minLength: 8)

                if window.resetsAt != nil {
                    Button(action: toggleResetDisplay) { resetLabel }
                        .buttonStyle(.plain)
                        .help(formatter.oppositeString(
                            for: window.resetsAt,
                            mode: resetDisplayMode,
                            now: now
                        ))
                } else {
                    resetLabel
                }
            }
        }
        .frame(width: QuotaBarLayout.width(for: period))
    }

    private var paceState: QuotaPaceState { window.paceState(at: now) }

    private var paceStatus: PaceStatus? {
        PaceFormatter.status(paceState, mode: resetDisplayMode, formatter: formatter, now: now)
    }

    @ViewBuilder
    private var paceWarning: some View {
        if let paceStatus {
            if case .runningOut(let runOutAt, _, _) = paceState, runOutAt != nil {
                Button(action: toggleResetDisplay) { paceLabel(paceStatus) }
                    .buttonStyle(.plain)
            } else {
                paceLabel(paceStatus)
            }
        }
    }

    private func paceLabel(_ status: PaceStatus) -> some View {
        HStack(spacing: 3) {
            if status.showsFlame {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }
            if let text = status.text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .help(paceTooltip)
    }

    private var resetLabel: some View {
        Text(formatter.string(for: window.resetsAt, mode: resetDisplayMode, now: now))
            .font(.caption)
            .foregroundStyle(Color.primary.opacity(0.72))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var paceTooltip: String {
        switch paceState {
        case .spent: return "额度已用完"
        case .healthy(let projected): return "重置时预计剩余 ~\(Int((100 - projected).rounded()))%"
        case .closeToLimit(_, let projected, _): return "重置时预计已用 ~\(Int(projected.rounded()))%"
        case .runningOut(_, let projected, _):
            guard projected > 100 else { return "重置时预计已用 ~100%" }
            return "重置时预计超出 ~\(max(1, Int((projected - 100).rounded())))%"
        case .level: return "刻度表示按当前时间进度理论上应剩余的额度"
        }
    }

}

private struct ContinuousQuotaBar: View {
    let period: QuotaPeriod
    let percent: Double
    let markerPercent: Double?
    let severity: QuotaPaceSeverity

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
        switch severity {
        case .normal: return Color(nsColor: .systemBlue)
        case .warning: return Color(nsColor: .systemYellow)
        case .critical: return Color(nsColor: .systemRed)
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
