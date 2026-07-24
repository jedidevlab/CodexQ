import SwiftUI

struct TokenCostSection: View {
    let snapshot: TokenCostSnapshot?
    let errorMessage: String?
    let isRefreshing: Bool
    let isPresented: Bool
    let contentDidChange: () -> Void

    @State private var hoveredKind: TokenCostPeriodSummary.Kind?
    @State private var pinnedKind: TokenCostPeriodSummary.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Token 成本")
                    .font(.headline)
                Text(scopeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                if let today = snapshot?.today {
                    periodButton(summary: today, compact: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: pinnedKind) { _, _ in contentDidChange() }
        .onChange(of: isPresented) { _, presented in
            guard !presented else { return }
            hoveredKind = nil
            pinnedKind = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    periodButton(summary: snapshot.yesterday)
                    if let subscription = snapshot.subscription {
                        periodButton(summary: subscription)
                    } else {
                        unavailableSubscriptionCard
                    }
                    periodButton(summary: snapshot.lifetime)
                }

                if let detail = activeSummary {
                    TokenCostDetailCard(
                        summary: detail,
                        subscriptionPeriod: snapshot.subscriptionPeriod,
                        dataScope: snapshot.dataScope
                    )
                }
                if snapshot.skippedSessionFileCount > 0 {
                    Text("有 \(snapshot.skippedSessionFileCount) 个会话文件未纳入成本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("这些本机 session 文件无法读取或不是普通 JSONL 文件，总金额可能偏低。")
                }
                if let syncMessage = snapshot.syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if let errorMessage {
                Text("Token 成本刷新失败，显示上次数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(errorMessage)
            }
        } else if let errorMessage {
            Text("Token 成本暂不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .help(errorMessage)
        } else if isRefreshing {
            ProgressView("正在计算 Token 成本...")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            Text("暂无本机 Token 成本数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
    }

    private func periodButton(
        summary: TokenCostPeriodSummary,
        compact: Bool = false
    ) -> some View {
        return Button {
            pinnedKind = pinnedKind == summary.kind ? nil : summary.kind
        } label: {
            if compact {
                HStack(spacing: 4) {
                    Text("今日")
                        .foregroundStyle(Color.primary.opacity(0.72))
                    Text(TokenCostFormatter.amount(summary))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(cardBackground(for: summary.kind), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(cardBorder(for: summary.kind), lineWidth: 1)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title(for: summary.kind))
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(TokenCostFormatter.amount(summary))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(TokenCountFormatter.compactNumber(summary.totalTokens))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(
                    cardBackground(for: summary.kind),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(cardBorder(for: summary.kind), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                hoveredKind = summary.kind
            } else if hoveredKind == summary.kind {
                hoveredKind = nil
            }
        }
        .help("点击查看模型明细")
        .accessibilityLabel(title(for: summary.kind))
        .accessibilityValue(
            "\(TokenCostFormatter.amount(summary))，"
                + TokenCountFormatter.string(summary.totalTokens)
        )
    }

    private var unavailableSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("本订阅周期")
                .font(.caption2)
                .foregroundStyle(Color.primary.opacity(0.72))
            Text("暂无周期")
                .font(.caption.weight(.semibold))
            Text("—")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var highlightedKind: TokenCostPeriodSummary.Kind? {
        pinnedKind ?? hoveredKind
    }

    private var activeSummary: TokenCostPeriodSummary? {
        guard let pinnedKind, let snapshot else { return nil }
        switch pinnedKind {
        case .today: return snapshot.today
        case .yesterday: return snapshot.yesterday
        case .subscription: return snapshot.subscription
        case .lifetime: return snapshot.lifetime
        }
    }

    private var scopeLabel: String {
        guard let scope = snapshot?.dataScope else { return "本机数据" }
        switch scope {
        case .local: return "本机数据"
        case .singleDevice: return "仅此设备"
        case .multiDevice: return "多设备数据"
        case .syncDelayed: return "多设备 · 同步延迟"
        case .syncBlocked: return "本机数据 · 同步暂停"
        case .partial: return "多设备 · 部分数据"
        }
    }

    private func title(for kind: TokenCostPeriodSummary.Kind) -> String {
        switch kind {
        case .today: return "今日"
        case .yesterday: return "昨日"
        case .subscription: return "本订阅周期"
        case .lifetime: return "累计"
        }
    }

    private func isActive(_ kind: TokenCostPeriodSummary.Kind) -> Bool {
        highlightedKind == kind
    }

    private func cardBackground(for kind: TokenCostPeriodSummary.Kind) -> Color {
        isActive(kind) ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.055)
    }

    private func cardBorder(for kind: TokenCostPeriodSummary.Kind) -> Color {
        isActive(kind) ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08)
    }

}

private struct TokenCostDetailCard: View {
    let summary: TokenCostPeriodSummary
    let subscriptionPeriod: DateInterval?
    let dataScope: TokenCostDataScope

    @State private var isSupplementExplanationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(detailTitle)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(displayedAmount)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            if summary.models.isEmpty {
                Text("该时段暂无本机用量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
            } else {
                ForEach(summary.models) { model in
                    modelRow(model)
                }
            }

            costBreakdown

            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func modelRow(_ model: TokenCostModelSummary) -> some View {
        let fraction = summary.recordedTokens > 0
            ? Double(model.totalTokens) / Double(summary.recordedTokens)
            : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.model)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(TokenCostFormatter.amount(model))
                    .font(.caption)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                Spacer()
                Text(TokenCountFormatter.string(model.totalTokens))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            GeometryReader { proxy in
                Capsule().fill(Color.secondary.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 4)
        }
        .help(
            "输入 \(TokenCountFormatter.compactNumber(model.inputTokens)) · "
                + "缓存 \(TokenCountFormatter.compactNumber(model.cachedInputTokens)) · "
                + "输出 \(TokenCountFormatter.compactNumber(model.outputTokens))"
        )
    }

    private var costBreakdown: some View {
        VStack(spacing: 4) {
            Divider()
                .opacity(0.55)
            costRow(
                label: "设备记录",
                tokens: summary.recordedTokens,
                amount: summary.recordedEstimatedCostUSD
            )
            if let supplement = summary.supplement {
                costRow(
                    label: "官方差额",
                    tokens: supplement.tokens,
                    amount: supplement.estimatedCostUSD,
                    showsSupplementInfo: true
                )
            }
        }
    }

    private func costRow(
        label: String,
        tokens: Int64,
        amount: Double,
        showsSupplementInfo: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
            Text(TokenCountFormatter.string(tokens))
                .foregroundStyle(.secondary)
            if showsSupplementInfo {
                Button {
                    isSupplementExplanationPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("解释官方差额")
                .accessibilityLabel("解释官方差额")
                .popover(isPresented: $isSupplementExplanationPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("官方差额说明")
                            .font(.caption.weight(.semibold))
                        Text("官方 Token 数据高于设备记录时，对没有明细的差额按设备记录平均单价估算。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(width: 210, alignment: .leading)
                }
            }
            Spacer()
            Text(TokenCostFormatter.amount(amount))
                .monospacedDigit()
        }
        .font(.caption2)
    }

    private var detailTitle: String {
        if summary.kind == .subscription, let subscriptionPeriod {
            return "本订阅周期 · \(date(subscriptionPeriod.start))–\(date(subscriptionPeriod.end))"
        }
        switch summary.kind {
        case .today: return "今日模型明细"
        case .yesterday: return "昨日模型明细"
        case .subscription: return "本订阅周期模型明细"
        case .lifetime: return "累计模型明细"
        }
    }

    private var footerText: String {
        switch dataScope {
        case .local, .syncBlocked:
            return "本机数据，按官方 API 价估算，非实际账单"
        case .singleDevice:
            return "仅此设备数据，按官方 API 价估算，非实际账单"
        case .multiDevice, .syncDelayed, .partial:
            return "多设备数据，按官方 API 价估算，非实际账单"
        }
    }

    private var displayedAmount: String {
        TokenCostFormatter.amount(summary)
    }

    private func date(_ value: Date) -> String {
        value.formatted(.dateTime.month().day())
    }
}
