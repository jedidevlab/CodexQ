import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshButtonBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tokenActivity: TokenActivitySnapshot?
    @Published private(set) var tokenActivityErrorMessage: String?
    @Published private(set) var isTokenActivityRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isPopoverPresented = false

    private let readRateLimits: () async throws -> QuotaSnapshot
    private let readTokenActivity: () async throws -> TokenActivitySnapshot
    private let saveCachedSnapshot: (CachedQuotaSnapshot) -> Void
    private let notifyQuotaCrossings: (QuotaSnapshot?, QuotaSnapshot) async -> Void
    private var refreshTask: Task<Void, Never>?
    private var tokenActivityTask: Task<Void, Never>?
    private var tokenActivityGeneration = 0

    init(
        readRateLimits: @escaping () async throws -> QuotaSnapshot = {
            try await AppServerClient().readRateLimits()
        },
        readTokenActivity: @escaping () async throws -> TokenActivitySnapshot = {
            try await AppServerClient().readTokenActivity()
        },
        loadCachedSnapshot: () -> CachedQuotaSnapshot? = SnapshotCache.load,
        saveCachedSnapshot: @escaping (CachedQuotaSnapshot) -> Void = SnapshotCache.save,
        notifyQuotaCrossings: ((QuotaSnapshot?, QuotaSnapshot) async -> Void)? = nil
    ) {
        self.readRateLimits = readRateLimits
        self.readTokenActivity = readTokenActivity
        self.saveCachedSnapshot = saveCachedSnapshot
        self.notifyQuotaCrossings = notifyQuotaCrossings ?? { previous, current in
            let settings = AppSettings.shared
            guard settings.notificationsEnabled else { return }
            let service = QuotaNotificationService()
            await service.requestAuthorization()
            await service.notifyCrossings(
                previous: previous,
                current: current,
                thresholds: settings.warningThresholds
            )
        }
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
        tokenActivityGeneration += 1
        tokenActivityTask?.cancel()
        tokenActivityTask = nil
        isTokenActivityRefreshing = false
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
        defer { isRefreshing = false }
        startTokenActivityRefreshIfNeeded()

        var quotaSucceeded = false
        do {
            let newSnapshot = try await readRateLimits()
            let updatedAt = Date()
            let previousSnapshot = snapshot
            snapshot = newSnapshot
            errorMessage = nil
            lastUpdatedAt = updatedAt
            saveCachedSnapshot(CachedQuotaSnapshot(snapshot: newSnapshot, updatedAt: updatedAt))
            await notifyQuotaCrossings(previousSnapshot, newSnapshot)
            quotaSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        return quotaSucceeded
    }

    func refreshFromButton() async {
        guard !isRefreshButtonBusy else { return }
        isRefreshButtonBusy = true
        defer { isRefreshButtonBusy = false }

        _ = await refresh()
        await tokenActivityTask?.value
    }

    private func startTokenActivityRefreshIfNeeded() {
        guard tokenActivityTask == nil else { return }
        tokenActivityGeneration += 1
        let generation = tokenActivityGeneration
        isTokenActivityRefreshing = true

        tokenActivityTask = Task { [weak self, readTokenActivity] in
            defer {
                if let self, self.tokenActivityGeneration == generation {
                    self.isTokenActivityRefreshing = false
                    self.tokenActivityTask = nil
                }
            }
            do {
                let activity = try await readTokenActivity()
                guard let self,
                      self.tokenActivityGeneration == generation,
                      !Task.isCancelled else { return }
                self.tokenActivity = activity
                self.tokenActivityErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.tokenActivityGeneration == generation,
                      !Task.isCancelled else { return }
                self.tokenActivity = nil
                self.tokenActivityErrorMessage = error.localizedDescription
            }
        }
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
