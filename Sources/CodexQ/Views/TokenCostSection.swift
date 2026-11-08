import SwiftUI

struct TokenCostSection: View {
    let snapshot: TokenCostSnapshot?
    let errorMessage: String?
    let isRefreshing: Bool
    let isPresented: Bool
    let contentWillChange: () -> Void
    let contentDidChange: () -> Void
    let showHistory: () -> Void

    @State private var hoveredKind: TokenCostPeriodSummary.Kind?
    @State private var pinnedKind: TokenCostPeriodSummary.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TokenHistoryNavigationButton(title: "Token 成本", action: showHistory)
                    .help("点击查看 Token 使用与成本历史")
                    .accessibilityLabel("打开 Token 使用与成本历史")
                Text(scopeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
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
            contentWillChange()
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pinnedKind = pinnedKind == summary.kind ? nil : summary.kind
            }
        } label: {
            if compact {
                HStack(spacing: 4) {
                    Text("今日")
                        .foregroundStyle(Color.primary.opacity(0.72))
                    Text(TokenCostFormatter.amount(summary))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.caption2)
                .layoutPriority(1)
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
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(summary.totalTokens == 0 && !summary.unquantifiedModels.isEmpty
                         ? "Token 未提供" : TokenCountFormatter.compactNumber(summary.totalTokens, fractionLength: 1))
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
                + (summary.totalTokens == 0 && !summary.unquantifiedModels.isEmpty
                   ? "Token 未提供" : TokenCountFormatter.string(summary.totalTokens))
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
        case .account: return "账号与本机数据"
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

struct TokenCostDetailCard: View {
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
                if summary.unquantifiedModels.isEmpty {
                    Text("该时段暂无本机用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
            } else {
                ForEach(summary.models) { model in
                    modelRow(model)
                }
            }

            if !summary.unquantifiedModels.isEmpty {
                Divider().opacity(0.55)
                Text("账号模型 · Token 明细未提供")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if summary.unquantifiedModels.count > 6 {
                    // Keep the newest model visible even while the remaining list scrolls.
                    if let first = summary.unquantifiedModels.first { unquantifiedModelRow(first) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(summary.unquantifiedModels.dropFirst()), id: \.self) { model in
                                unquantifiedModelRow(model)
                            }
                        }
                    }
                    .frame(height: 100)
                } else {
                    ForEach(summary.unquantifiedModels, id: \.self) { model in
                        unquantifiedModelRow(model)
                    }
                }
                Text("账号接口没有 Token 数，不能从额度占比推算；零值不代表未使用，金额只含已知成本。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !summary.models.isEmpty || summary.supplement != nil {
                costBreakdown
            }

            if summary.unpricedTokens > 0 {
                Text("未计价 Token：\(TokenCountFormatter.string(summary.unpricedTokens))。缺少逐次请求明细或价格；金额旁的 + 表示仅计入已知成本。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(footerText)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func unquantifiedModelRow(_ model: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 6)
            Text("Token 未提供").font(.caption2).foregroundStyle(.secondary)
        }
        .help("账号接口列出的模型名称不代表每个模型都已在该时段产生用量。")
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
            model.unpricedTokens > 0
                ? "含未计价 Token；账号日汇总没有逐次请求的输入、缓存和输出明细。"
                : "输入 \(TokenCountFormatter.compactNumber(model.inputTokens)) · "
                + "缓存 \(TokenCountFormatter.compactNumber(model.cachedInputTokens)) · "
                + "输出 \(TokenCountFormatter.compactNumber(model.outputTokens))"
        )
    }

    private var costBreakdown: some View {
        VStack(spacing: 4) {
            Divider()
                .opacity(0.55)
            if !summary.models.isEmpty {
                costRow(
                    label: "模型记录",
                    tokens: summary.recordedTokens,
                    amount: summary.recordedTokens == summary.unpricedTokens && summary.unpricedTokens > 0
                        ? nil : summary.recordedEstimatedCostUSD,
                    hasUnpricedTokens: summary.unpricedTokens > 0
                )
            }
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
        amount: Double?,
        hasUnpricedTokens: Bool = false,
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
                        Text("官方 Token 数据高于模型记录时，对没有明细的差额按已计价记录的平均单价估算；没有可用单价时标为未计价。差额不能分配给某个具体模型。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(width: 210, alignment: .leading)
                }
            }
            Spacer()
            Text(TokenCostFormatter.amount(amount) + (hasUnpricedTokens && amount != nil ? "+" : ""))
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
        case .account:
            return "含账号日汇总，补入部分未计价；已知成本按 API 价估算，非实际账单"
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
