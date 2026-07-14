import SwiftUI

struct TokenActivitySection: View {
    let snapshot: TokenActivitySnapshot?
    let errorMessage: String?
    let isRefreshing: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Token 活动")
                    .font(.headline)
                Spacer(minLength: 8)
                if let snapshot {
                    let latestDay = TokenActivityPresentation.latestRecordedDay(
                        through: now,
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
        if let errorMessage {
            Text("Token 活动暂不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .help(errorMessage)
        } else if let snapshot {
            let cells = TokenActivityPresentation.dailyCells(
                snapshot: snapshot,
                now: now,
                calendar: calendar
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

private struct TokenActivityInlineSummary: View {
    let completedDayLabel: String
    let completedDayTokens: Int64?
    let lifetimeTokens: Int64?

    var body: some View {
        HStack(spacing: 10) {
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
                .foregroundStyle(.secondary)
            Text(tokens.map(TokenCountFormatter.compactNumber) ?? "暂无数据")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(tokens.map(TokenCountFormatter.string) ?? "暂无数据")
    }
}

private enum TokenActivityGridLayout {
    static let squareSize: CGFloat = 10
    static let spacing: CGFloat = 2
    static let monthSpacing: CGFloat = 8

    static var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(squareSize), spacing: spacing),
            count: 7
        )
    }
}

private struct DailyTokenActivityGrid: View {
    let cells: [TokenActivityCell]
    let peakTokens: Int64
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: TokenActivityGridLayout.monthSpacing) {
            ForEach(months) { month in
                VStack(spacing: 3) {
                    Text(monthText(month.start))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: TokenActivityGridLayout.columns, spacing: TokenActivityGridLayout.spacing) {
                        ForEach(0..<month.leadingBlankCount, id: \.self) { _ in
                            Color.clear
                                .frame(
                                    width: TokenActivityGridLayout.squareSize,
                                    height: TokenActivityGridLayout.squareSize
                                )
                        }
                        ForEach(month.cells, id: \.date) { cell in
                            DailyActivitySquare(
                                cell: cell,
                                peakTokens: peakTokens,
                                calendar: calendar
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var months: [ActivityMonth] {
        var result: [ActivityMonth] = []
        for cell in cells {
            let components = calendar.dateComponents([.year, .month], from: cell.date)
            guard let start = calendar.date(from: components) else { continue }
            if result.last?.start == start {
                result[result.count - 1].cells.append(cell)
            } else {
                result.append(ActivityMonth(
                    start: start,
                    leadingBlankCount: (calendar.component(.weekday, from: start) + 5) % 7,
                    cells: [cell]
                ))
            }
        }
        return result
    }

    private func monthText(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.year().month(.abbreviated)
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return date.formatted(format)
    }
}

private struct ActivityMonth: Identifiable {
    let start: Date
    let leadingBlankCount: Int
    var cells: [TokenActivityCell]

    var id: Date { start }
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

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .overlay {
                if level == nil {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            Color.secondary.opacity(0.1),
                            lineWidth: 0.5
                        )
                }
            }
            .frame(
                width: TokenActivityGridLayout.squareSize,
                height: TokenActivityGridLayout.squareSize
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }

    private var fillColor: Color {
        guard let level else {
            return Color.secondary.opacity(0.07)
        }
        switch level {
        case 0: return Color.secondary.opacity(0.22)
        case 1: return Color.accentColor.opacity(0.25)
        case 2: return Color.accentColor.opacity(0.42)
        case 3: return Color.accentColor.opacity(0.65)
        default: return Color.accentColor.opacity(0.9)
        }
    }
}
