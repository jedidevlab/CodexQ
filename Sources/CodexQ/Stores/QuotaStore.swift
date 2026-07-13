import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tokenActivity: TokenActivitySnapshot?
    @Published private(set) var tokenActivityErrorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isPopoverPresented = false

    private let readRateLimits: () async throws -> QuotaSnapshot
    private let readTokenActivity: () async throws -> TokenActivitySnapshot
    private let saveCachedSnapshot: (CachedQuotaSnapshot) -> Void
    private let notificationsEnabled: () -> Bool
    private let settings = AppSettings.shared
    private let notificationService = QuotaNotificationService()
    private var refreshTask: Task<Void, Never>?

    init(
        readRateLimits: @escaping () async throws -> QuotaSnapshot = {
            try await AppServerClient().readRateLimits()
        },
        readTokenActivity: @escaping () async throws -> TokenActivitySnapshot = {
            try await AppServerClient().readTokenActivity()
        },
        loadCachedSnapshot: () -> CachedQuotaSnapshot? = SnapshotCache.load,
        saveCachedSnapshot: @escaping (CachedQuotaSnapshot) -> Void = SnapshotCache.save,
        notificationsEnabled: @escaping () -> Bool = { AppSettings.shared.notificationsEnabled }
    ) {
        self.readRateLimits = readRateLimits
        self.readTokenActivity = readTokenActivity
        self.saveCachedSnapshot = saveCachedSnapshot
        self.notificationsEnabled = notificationsEnabled
        if let cached = loadCachedSnapshot() {
            snapshot = cached.snapshot
            lastUpdatedAt = cached.updatedAt
        }
    }

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task {
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let didRefresh = await refresh()
                do {
                    try await clock.sleep(
                        for: QuotaRefreshPolicy.intervalAfterRefresh(succeeded: didRefresh),
                        tolerance: .seconds(1)
                    )
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

    func refreshIfNeededOnPresentation(now: Date = Date()) async {
        guard QuotaRefreshPolicy.shouldRefreshOnPresentation(
            remainingPercent: snapshot?.statusRemainingPercent,
            lastUpdatedAt: lastUpdatedAt,
            errorMessage: errorMessage,
            isRefreshing: isRefreshing,
            now: now
        ) else {
            return
        }
        await refresh()
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        errorMessage = nil
        tokenActivityErrorMessage = nil
        defer { isRefreshing = false }

        var quotaSucceeded = false
        do {
            let newSnapshot = try await readRateLimits()
            let updatedAt = Date()
            let previousSnapshot = snapshot
            snapshot = newSnapshot
            lastUpdatedAt = updatedAt
            saveCachedSnapshot(CachedQuotaSnapshot(snapshot: newSnapshot, updatedAt: updatedAt))
            if notificationsEnabled() {
                await notificationService.requestAuthorization()
                await notificationService.notifyCrossings(
                    previous: previousSnapshot,
                    current: newSnapshot,
                    thresholds: settings.warningThresholds
                )
            }
            quotaSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            tokenActivity = try await readTokenActivity()
        } catch {
            tokenActivity = nil
            tokenActivityErrorMessage = error.localizedDescription
        }

        return quotaSucceeded
    }
}

enum QuotaRefreshPolicy {
    static let successInterval: Duration = .seconds(180)
    static let failureInterval: Duration = .seconds(15)

    static func intervalAfterRefresh(succeeded: Bool) -> Duration {
        succeeded ? successInterval : failureInterval
    }

    static func shouldRefreshOnPresentation(
        remainingPercent: Double?,
        lastUpdatedAt: Date?,
        errorMessage: String?,
        isRefreshing: Bool,
        now: Date
    ) -> Bool {
        guard !isRefreshing else { return false }
        if errorMessage != nil { return true }
        return !StatusTitleFormatter.hasFreshQuota(
            remainingPercent: remainingPercent,
            lastUpdatedAt: lastUpdatedAt,
            now: now
        )
    }
}
