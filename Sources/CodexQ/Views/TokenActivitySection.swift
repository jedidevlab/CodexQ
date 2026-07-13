import SwiftUI

struct TokenActivitySection: View {
    let snapshot: TokenActivitySnapshot?
    let errorMessage: String?
    let isRefreshing: Bool
    let now: Date

    @State private var mode: Mode = .daily

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Token 活动")
                    .font(.headline)
                Spacer()
                Picker("Token 活动范围", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 116)
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
            switch mode {
            case .daily:
                DailyTokenActivityGrid(snapshot: snapshot, now: now, calendar: calendar)
            case .weekly:
                WeeklyTokenActivityGrid(snapshot: snapshot, now: now, calendar: calendar)
            }

            if snapshot.days.isEmpty {
                Text("暂无 Token 使用记录")
                    .font(.caption2)
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
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }
}

private extension TokenActivitySection {
    enum Mode: String, CaseIterable, Identifiable {
        case daily
        case weekly

        var id: Self { self }

        var title: String {
            switch self {
            case .daily: return "每日"
            case .weekly: return "每周"
            }
        }
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
    let snapshot: TokenActivitySnapshot
    let now: Date
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: TokenActivityGridLayout.monthSpacing) {
            ForEach(months) { month in
                VStack(spacing: 3) {
                    Text(month.start, format: .dateTime.year().month(.abbreviated))
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
                                peakTokens: snapshot.peakDailyTokens
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var months: [ActivityMonth] {
        let cells = TokenActivityPresentation.dailyCells(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
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
}

private struct WeeklyTokenActivityGrid: View {
    let snapshot: TokenActivitySnapshot
    let now: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: TokenActivityGridLayout.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: TokenActivityGridLayout.spacing) {
                    Text(row.cells.first.map { weekLabel($0.date) } ?? "")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    ForEach(row.cells, id: \.date) { cell in
                        WeeklyActivitySquare(
                            cell: cell,
                            peakTokens: snapshot.peakDailyTokens,
                            isOutsideRange: cell.date < statisticalStart || cell.date > statisticalEnd
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [TokenActivityWeek] {
        TokenActivityPresentation.weeklyRows(
            snapshot: snapshot,
            now: now,
            calendar: calendar
        )
    }

    private var statisticalEnd: Date {
        calendar.startOfDay(for: now)
    }

    private var statisticalStart: Date {
        guard let lowerMonth = calendar.date(byAdding: .month, value: -1, to: statisticalEnd),
              let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: lowerMonth)
              ) else {
            return statisticalEnd
        }
        return start
    }

    private func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month().day())
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

    var body: some View {
        let level = cell.tokens.map {
            TokenActivityLevel.level(tokens: $0, peakTokens: peakTokens)
        }
        TokenActivitySquare(level: level, isOutsideRange: false)
            .help(cell.tokens.map {
                "\(dateText) · \(TokenCountFormatter.string($0))"
            } ?? "\(dateText) · 无数据")
    }

    private var dateText: String {
        cell.date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct WeeklyActivitySquare: View {
    let cell: TokenActivityCell
    let peakTokens: Int64
    let isOutsideRange: Bool

    var body: some View {
        let level = cell.tokens.map {
            TokenActivityLevel.level(tokens: $0, peakTokens: peakTokens)
        }
        TokenActivitySquare(level: level, isOutsideRange: isOutsideRange)
            .help(cell.tokens.map {
                "\(dateText) · \(TokenCountFormatter.string($0))"
            } ?? "\(dateText) · \(isOutsideRange ? "范围外" : "无数据")")
    }

    private var dateText: String {
        cell.date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TokenActivitySquare: View {
    let level: Int?
    let isOutsideRange: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .overlay {
                if level == nil {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(
                            Color.secondary.opacity(isOutsideRange ? 0.2 : 0.1),
                            style: StrokeStyle(
                                lineWidth: 0.5,
                                dash: isOutsideRange ? [2, 1] : []
                            )
                        )
                }
            }
            .frame(
                width: TokenActivityGridLayout.squareSize,
                height: TokenActivityGridLayout.squareSize
            )
    }

    private var fillColor: Color {
        guard let level else {
            return isOutsideRange ? .clear : Color.secondary.opacity(0.07)
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
