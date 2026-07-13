enum PopoverInteraction: CaseIterable, Hashable, Sendable {
    case pointer
    case resetCredits
    case settings
}

enum PopoverAutoClosePolicy {
    static func shouldSchedule(
        isQuotaRefreshing: Bool,
        isTokenActivityRefreshing: Bool,
        activeInteractions: Set<PopoverInteraction>
    ) -> Bool {
        !isQuotaRefreshing
            && !isTokenActivityRefreshing
            && activeInteractions.isEmpty
    }
}
