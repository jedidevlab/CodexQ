import AppKit
import SwiftUI

struct TokenActivitySection: View {
    let snapshot: TokenActivitySnapshot?
    let errorMessage: String?
    let isRefreshing: Bool
    let now: Date
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TokenHistoryNavigationButton(title: "Token 活动", action: showHistory)
                    .help("点击查看 Token 活动历史")
                    .accessibilityLabel("打开 Token 活动历史")
                Spacer(minLength: 6)
                if let snapshot {
                    let latestDay = TokenActivityPresentation.latestRecordedDay(
                        before: now,
                        snapshot: snapshot,
                        calendar: calendar
                    )
                    TokenActivityInlineSummary(
                        completedDayLabel: latestDay.map {
                            TokenActivityDateLabel.string(
                                for: $0.date,
                                now: now,
                                calendar: calendar
                            )
                        } ?? "最近",
                        completedDayTokens: latestDay?.tokens,
                        lifetimeTokens: snapshot.lifetimeTokens
                    )
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            let cells = TokenActivityPresentation.dailyCells(
                snapshot: snapshot,
                now: now,
                calendar: calendar,
                weekCount: TokenActivityGridLayout.weekCount
            )
            DailyTokenActivityGrid(
                cells: cells,
                peakTokens: snapshot.peakDailyTokens,
                calendar: calendar
            )
            if !TokenActivityPresentation.hasRecordedTokens(in: cells) {
                Text("暂无 Token 使用记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage {
            Text("Token 活动暂不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .help(errorMessage)
        } else if isRefreshing {
            ProgressView("正在读取 Token 活动...")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 54)
        } else {
            Text("暂无 Token 活动数据")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }
}

struct TokenHistoryNavigationButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            TokenHistoryNavigationLabel(title: title, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            TokenHistoryNavigationCursor.update(isHovered: hovering)
        }
        .onDisappear {
            if isHovered {
                TokenHistoryNavigationCursor.update(isHovered: false)
            }
        }
    }
}

struct TokenHistoryNavigationLabel: View {
    let title: String
    let isHovered: Bool

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.primary.opacity(isHovered ? 0.55 : 1))
            .contentShape(Rectangle())
    }
}

enum TokenHistoryNavigationCursor {
    static func update(isHovered: Bool) {
        if isHovered {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

private struct TokenActivityInlineSummary: View {
    let completedDayLabel: String
    let completedDayTokens: Int64?
    let lifetimeTokens: Int64?

    var body: some View {
        HStack(spacing: 8) {
            metric(
                label: completedDayLabel,
                accessibilityLabel: "\(completedDayLabel) Token",
                tokens: completedDayTokens
            )
            metric(label: "累计", accessibilityLabel: "累计 Token", tokens: lifetimeTokens)
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func metric(
        label: String,
        accessibilityLabel: String,
        tokens: Int64?
    ) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(Color.primary.opacity(0.72))
            Text(tokens.map { TokenCountFormatter.compactNumber($0, fractionLength: 1) } ?? "暂无数据")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(tokens.map(TokenCountFormatter.string) ?? "暂无数据")
    }
}

private enum TokenActivityGridLayout {
    static let contentWidth = QuotaPopoverLayout.width
        - QuotaPopoverLayout.horizontalPadding * 2
    static let squareSize: CGFloat = 11
    static let minimumSpacing: CGFloat = 3
    static let weekCount = max(
        1,
        Int((contentWidth + minimumSpacing) / (squareSize + minimumSpacing))
    )
    static let spacing = weekCount > 1
        ? (contentWidth - squareSize * CGFloat(weekCount)) / CGFloat(weekCount - 1)
        : 0
    static let gridWidth = contentWidth
}

private struct DailyTokenActivityGrid: View {
    let cells: [TokenActivityCell]
    let peakTokens: Int64
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: TokenActivityGridLayout.spacing) {
                ForEach(weeks) { week in
                    VStack(spacing: TokenActivityGridLayout.spacing) {
                        ForEach(week.cells, id: \.date) { cell in
                            DailyActivitySquare(
                                cell: cell,
                                peakTokens: peakTokens,
                                calendar: calendar
                            )
                        }
                    }
                }
            }

            HStack(spacing: TokenActivityGridLayout.spacing) {
                ForEach(monthSpans) { span in
                    Text(monthText(span.start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(
                            width: span.width,
                            alignment: span.id == monthSpans.last?.id ? .trailing : .center
                        )
                }
            }
            .frame(width: TokenActivityGridLayout.gridWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeks: [ActivityWeek] {
        stride(from: 0, to: cells.count, by: 7).map { offset in
            let end = min(offset + 7, cells.count)
            let weekCells = Array(cells[offset..<end])
            return ActivityWeek(start: weekCells[0].date, cells: weekCells)
        }
    }

    private var monthSpans: [ActivityMonthSpan] {
        weeks.reduce(into: []) { result, week in
            let components = calendar.dateComponents([.year, .month], from: week.start)
            guard let start = calendar.date(from: components) else { return }
            if result.last?.start == start {
                result[result.count - 1].weekCount += 1
            } else {
                result.append(ActivityMonthSpan(start: start, weekCount: 1))
            }
        }
    }

    private func monthText(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.month(.abbreviated)
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return date.formatted(format)
    }
}

private struct ActivityWeek: Identifiable {
    let start: Date
    let cells: [TokenActivityCell]

    var id: Date { start }
}

private struct ActivityMonthSpan: Identifiable {
    let start: Date
    var weekCount: Int

    var id: Date { start }

    var width: CGFloat {
        TokenActivityGridLayout.squareSize * CGFloat(weekCount)
            + TokenActivityGridLayout.spacing * CGFloat(weekCount - 1)
    }
}

private struct DailyActivitySquare: View {
    let cell: TokenActivityCell
    let peakTokens: Int64
    let calendar: Calendar

    var body: some View {
        let level = cell.tokens.map {
            TokenActivityLevel.level(tokens: $0, peakTokens: peakTokens)
        }
        TokenActivitySquare(
            level: level,
            accessibilityLabel: dateText,
            accessibilityValue: tokenText
        )
        .help("\(dateText) · \(tokenText)")
    }

    private var dateText: String {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return cell.date.formatted(format)
    }

    private var tokenText: String {
        cell.tokens.map(TokenCountFormatter.string) ?? "无数据"
    }
}

private struct TokenActivitySquare: View {
    let level: Int?
    let accessibilityLabel: String
    let accessibilityValue: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(TokenActivityHeatmapPalette.color(level: level, colorScheme: colorScheme))
            .frame(
                width: TokenActivityGridLayout.squareSize,
                height: TokenActivityGridLayout.squareSize
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }

}

enum TokenActivityHeatmapPalette {
    static func hex(level: Int?, colorScheme: ColorScheme) -> UInt32 {
        let normalizedLevel = min(4, max(0, level ?? 0))
        switch colorScheme {
        case .dark:
            return [0x303030, 0x013566, 0x004F99, 0x0285FF, 0x66B5FF][normalizedLevel]
        default:
            return [0xF3F3F3, 0xCCE6FF, 0x66B5FF, 0x0285FF, 0x004F99][normalizedLevel]
        }
    }

    static func color(level: Int?, colorScheme: ColorScheme) -> Color {
        let value = hex(level: level, colorScheme: colorScheme)
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
