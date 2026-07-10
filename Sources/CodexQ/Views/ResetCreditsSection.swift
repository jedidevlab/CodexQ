import SwiftUI

struct ResetCreditsSection: View {
    let summary: ResetCreditsSummary
    @State private var isExpanded = false

    var body: some View {
        let presentation = ResetCreditPresentation(summary: summary)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("限额重置")
                        .font(.headline)
                    Spacer()
                    Text(presentation.countText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(
                            summary.availableCount > 0 ? Color.green : Color.secondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            summary.availableCount > 0
                                ? Color.green.opacity(0.16)
                                : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let emptyMessage = presentation.emptyMessage {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(presentation.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                Spacer(minLength: 8)
                                Text(row.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)

                            if row.id != presentation.rows.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
