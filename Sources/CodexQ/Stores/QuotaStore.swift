import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isPopoverPresented = false

    private let client = AppServerClient()
    private let settings = AppSettings.shared
    private let notificationService = QuotaNotificationService()
    private var refreshTask: Task<Void, Never>?

    init() {
        if let cached = SnapshotCache.load() {
            snapshot = cached.snapshot
            lastUpdatedAt = cached.updatedAt
        }
    }

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let nextRefresh = clock.now.advanced(by: .seconds(180))
                await refresh()
                do {
                    try await clock.sleep(until: nextRefresh, tolerance: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func setPopoverPresented(_ isPresented: Bool) {
        isPopoverPresented = isPresented
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newSnapshot = try await client.readRateLimits()
            let updatedAt = Date()
            let previousSnapshot = snapshot
            snapshot = newSnapshot
            lastUpdatedAt = updatedAt
            errorMessage = nil
            SnapshotCache.save(CachedQuotaSnapshot(snapshot: newSnapshot, updatedAt: updatedAt))
            if settings.notificationsEnabled {
                await notificationService.requestAuthorization()
                await notificationService.notifyCrossings(
                    previous: previousSnapshot,
                    current: newSnapshot,
                    thresholds: settings.warningThresholds
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
