import Combine
import Foundation

@MainActor
final class TokenHistoryStore: ObservableObject {
    @Published var mode: TokenHistoryRangeMode
    @Published var selectedDay: Date
    @Published var selectedYear: Int
    @Published var selectedMonth: Int
    @Published var selectedSubscriptionInterval: DateInterval?
    @Published var customStart: Date
    @Published var customEnd: Date
    @Published private(set) var snapshot: TokenHistorySnapshot?
    @Published private(set) var isLoading: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableSubscriptionCycles: [SubscriptionCycle]

    private let reader: TokenHistoryReader
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(
        reader: TokenHistoryReader = TokenHistoryReader(),
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.reader = reader
        self.calendar = calendar
        self.now = now
        let initialNow = now()
        mode = .month
        selectedDay = initialNow
        let components = calendar.dateComponents([.year, .month], from: initialNow)
        selectedYear = components.year ?? 1970
        selectedMonth = components.month ?? 1
        selectedSubscriptionInterval = nil
        customStart = calendar.date(byAdding: .day, value: -29, to: initialNow) ?? initialNow
        customEnd = initialNow
        snapshot = nil
        isLoading = false
        errorMessage = nil
        availableSubscriptionCycles = []
    }

    var selectionIdentity: TokenHistorySelection { selection }

    var visibleSnapshot: TokenHistorySnapshot? {
        guard snapshot?.selection == selection else { return nil }
        return snapshot
    }

    var selection: TokenHistorySelection {
        switch mode {
        case .day:
            return .day(selectedDay)
        case .month:
            return .month(year: selectedYear, month: selectedMonth)
        case .year:
            return .year(selectedYear)
        case .subscription:
            guard let interval = selectedSubscriptionInterval
                ?? availableSubscriptionCycles.first?.interval else {
                return .month(year: selectedYear, month: selectedMonth)
            }
            return .subscription(interval)
        case .cumulative:
            return .cumulative
        case .custom:
            return .custom(start: customStart, endInclusive: customEnd)
        }
    }

    func loadIfNeeded() {
        guard snapshot?.selection != selection || errorMessage != nil else { return }
        reload()
    }

    func reload() {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let requestedSelection = selection
        let requestedNow = now()
        let reader = reader
        let calendar = calendar
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            do {
                let value = try await reader.read(
                    selection: requestedSelection,
                    now: requestedNow,
                    calendar: calendar
                )
                guard let self,
                      !Task.isCancelled,
                      self.loadGeneration == generation else {
                    return
                }
                self.snapshot = value
                self.availableSubscriptionCycles = value.subscriptionCycles
                if self.selectedSubscriptionInterval == nil {
                    self.selectedSubscriptionInterval = value.subscriptionCycles.first?.interval
                }
                self.errorMessage = nil
                self.isLoading = false
            } catch is CancellationError {
                guard let self, self.loadGeneration == generation else { return }
                self.isLoading = false
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.loadGeneration == generation else {
                    return
                }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }
}
