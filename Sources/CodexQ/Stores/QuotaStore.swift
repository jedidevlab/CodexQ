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

    private let readDashboardSnapshots: (@Sendable () async throws -> AppServerSnapshots)?
    private let readRateLimits: @Sendable () async throws -> QuotaSnapshot
    private let readTokenActivity: @Sendable () async throws -> TokenActivitySnapshot
    private let saveCachedSnapshot: (CachedQuotaSnapshot) -> Void
    private let notifyQuotaCrossings: (QuotaSnapshot?, QuotaSnapshot) async -> Void
    private var refreshTask: Task<Void, Never>?
    private var tokenActivityTask: Task<Void, Never>?
    private var tokenActivityGeneration = 0

    init(
        readDashboardSnapshots: (@Sendable () async throws -> AppServerSnapshots)? = nil,
        readRateLimits: (@Sendable () async throws -> QuotaSnapshot)? = nil,
        readTokenActivity: (@Sendable () async throws -> TokenActivitySnapshot)? = nil,
        loadCachedSnapshot: () -> CachedQuotaSnapshot? = SnapshotCache.load,
        saveCachedSnapshot: @escaping (CachedQuotaSnapshot) -> Void = SnapshotCache.save,
        notifyQuotaCrossings: ((QuotaSnapshot?, QuotaSnapshot) async -> Void)? = nil
    ) {
        let hasSeparateAppServerReaders = readRateLimits != nil || readTokenActivity != nil
        if let readDashboardSnapshots {
            self.readDashboardSnapshots = readDashboardSnapshots
        } else if hasSeparateAppServerReaders {
            self.readDashboardSnapshots = nil
        } else {
            self.readDashboardSnapshots = { @Sendable in
                try await AppServerClient().readDashboardSnapshots()
            }
        }
        self.readRateLimits = readRateLimits ?? {
            try await AppServerClient().readRateLimits()
        }
        self.readTokenActivity = readTokenActivity ?? {
            try await AppServerClient().readTokenActivity()
        }
        self.saveCachedSnapshot = saveCachedSnapshot
        self.notifyQuotaCrossings = notifyQuotaCrossings ?? { previous, current in
            let settings = AppSettings.shared
            guard settings.notificationsEnabled else { return }
            let service = QuotaNotificationService()
            let granted = await service.requestAuthorizationIfNeeded()
            settings.updateNotificationPermissionWarning(authorizationGranted: granted)
            guard NotificationAuthorizationPolicy.canSendNotifications(authorizationGranted: granted) else { return }
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
        if readDashboardSnapshots != nil {
            isTokenActivityRefreshing = true
        } else {
            startTokenActivityRefreshIfNeeded()
        }
        defer {
            isRefreshing = false
            if readDashboardSnapshots != nil {
                isTokenActivityRefreshing = false
            }
        }

        do {
            let newSnapshot: QuotaSnapshot
            if let readDashboardSnapshots {
                do {
                    let dashboard = try await readDashboardSnapshots()
                    newSnapshot = dashboard.quota
                    tokenActivity = dashboard.tokenActivity
                    tokenActivityErrorMessage = nil
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    tokenActivityErrorMessage = error.localizedDescription
                    async let fallbackActivity = loadActivity()
                    newSnapshot = try await readRateLimits()
                    applyActivityResult(await fallbackActivity)
                }
            } else {
                newSnapshot = try await readRateLimits()
            }

            let updatedAt = Date()
            let previousSnapshot = snapshot
            let resolvedSnapshot = Self.preservingRecentResetCreditDetails(
                in: newSnapshot,
                from: previousSnapshot,
                now: updatedAt
            )
            snapshot = resolvedSnapshot
            errorMessage = nil
            lastUpdatedAt = updatedAt
            saveCachedSnapshot(CachedQuotaSnapshot(
                snapshot: resolvedSnapshot,
                updatedAt: updatedAt
            ))
            await notifyQuotaCrossings(previousSnapshot, resolvedSnapshot)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshFromButton() async {
        guard !isRefreshButtonBusy else { return }
        isRefreshButtonBusy = true
        defer { isRefreshButtonBusy = false }
        _ = await refresh()
    }

    private enum ActivityResult: Sendable {
        case success(TokenActivitySnapshot)
        case failure(String)
        case cancelled
    }

    private func loadActivity() async -> ActivityResult {
        do {
            return .success(try await readTokenActivity())
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func applyActivityResult(_ result: ActivityResult) {
        switch result {
        case .success(let activity):
            tokenActivity = activity
            tokenActivityErrorMessage = nil
        case .failure(let message):
            tokenActivityErrorMessage = message
        case .cancelled:
            break
        }
    }

    private func startTokenActivityRefreshIfNeeded() {
        guard tokenActivityTask == nil else { return }
        tokenActivityGeneration += 1
        let generation = tokenActivityGeneration
        isTokenActivityRefreshing = true

        tokenActivityTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.loadActivity()
            guard self.tokenActivityGeneration == generation, !Task.isCancelled else { return }
            self.applyActivityResult(result)
            self.isTokenActivityRefreshing = false
            self.tokenActivityTask = nil
        }
    }

    private static func preservingRecentResetCreditDetails(
        in snapshot: QuotaSnapshot,
        from previousSnapshot: QuotaSnapshot?,
        now: Date
    ) -> QuotaSnapshot {
        guard let summary = snapshot.resetCredits,
              summary.availableCount > 0,
              summary.availableCredits.isEmpty,
              let previousSummary = previousSnapshot?.resetCredits,
              previousSummary.availableCount == summary.availableCount else {
            return snapshot
        }
        let recentCredits = previousSummary.availableCredits.filter {
            $0.expiresAt.map { $0 > now } ?? true
        }
        guard !recentCredits.isEmpty else { return snapshot }
        return QuotaSnapshot(
            fiveHour: snapshot.fiveHour,
            weekly: snapshot.weekly,
            resetCredits: ResetCreditsSummary(
                availableCount: summary.availableCount,
                credits: recentCredits
            ),
            planType: snapshot.planType
        )
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
