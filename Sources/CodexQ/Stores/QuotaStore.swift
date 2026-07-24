import Foundation

private enum TokenRefreshResult: Sendable {
    case activity(TokenActivitySnapshot?, String?)
    case cost(TokenCostSnapshot?, String?)
}

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshButtonBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tokenActivity: TokenActivitySnapshot?
    @Published private(set) var tokenActivityErrorMessage: String?
    @Published private(set) var tokenCost: TokenCostSnapshot?
    @Published private(set) var tokenCostErrorMessage: String?
    @Published private(set) var isTokenActivityRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isPopoverPresented = false

    private let readDashboardSnapshots: (@Sendable () async throws -> AppServerSnapshots)?
    private let readRateLimits: @Sendable () async throws -> QuotaSnapshot
    private let readTokenActivity: @Sendable () async throws -> TokenActivitySnapshot
    private let readTokenCost: @Sendable () async throws -> TokenCostSnapshot
    private let saveCachedSnapshot: (CachedQuotaSnapshot) -> Void
    private let notifyQuotaCrossings: (QuotaSnapshot?, QuotaSnapshot) async -> Void
    private let costSyncChangeDebounce: Duration
    private var refreshTask: Task<Void, Never>?
    private var tokenActivityTask: Task<Void, Never>?
    private var costSyncChangeTask: Task<Void, Never>?
    private var costSyncDebounceTask: Task<Void, Never>?
    private var tokenActivityGeneration = 0
    private var pendingCostSyncRefresh = false
    private var recordedTokenCost: TokenCostSnapshot?

    init(
        readDashboardSnapshots: (@Sendable () async throws -> AppServerSnapshots)? = nil,
        readRateLimits: (@Sendable () async throws -> QuotaSnapshot)? = nil,
        readTokenActivity: (@Sendable () async throws -> TokenActivitySnapshot)? = nil,
        readTokenCost: @escaping @Sendable () async throws -> TokenCostSnapshot = {
            try await readCurrentTokenCost()
        },
        costSyncChangeEvents: (@Sendable () -> AsyncStream<Void>)? = nil,
        costSyncChangeDebounce: Duration = .seconds(2),
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
        self.readTokenCost = readTokenCost
        self.costSyncChangeDebounce = costSyncChangeDebounce
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
        if let costSyncChangeEvents {
            costSyncChangeTask = Task { [weak self] in
                for await _ in costSyncChangeEvents() {
                    guard let self, !Task.isCancelled else { return }
                    self.scheduleTokenCostRefreshFromSyncChange()
                }
            }
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
        costSyncChangeTask?.cancel()
        costSyncChangeTask = nil
        costSyncDebounceTask?.cancel()
        costSyncDebounceTask = nil
        pendingCostSyncRefresh = false
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
        if readDashboardSnapshots != nil {
            startTokenCostRefreshIfNeeded()
        } else {
            startTokenActivityRefreshIfNeeded()
        }

        var quotaSucceeded = false
        do {
            let newSnapshot: QuotaSnapshot
            if let readDashboardSnapshots {
                do {
                    let dashboard = try await readDashboardSnapshots()
                    newSnapshot = dashboard.quota
                    tokenActivity = dashboard.tokenActivity
                    tokenActivityErrorMessage = nil
                    publishTokenCost()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    tokenActivityErrorMessage = error.localizedDescription
                    async let fallbackActivity: TokenRefreshResult = {
                        do {
                            return .activity(try await readTokenActivity(), nil)
                        } catch is CancellationError {
                            return .activity(nil, nil)
                        } catch {
                            return .activity(nil, error.localizedDescription)
                        }
                    }()
                    newSnapshot = try await readRateLimits()
                    switch await fallbackActivity {
                    case let .activity(activity, errorMessage):
                        if let activity {
                            tokenActivity = activity
                            tokenActivityErrorMessage = nil
                            publishTokenCost()
                        } else if let errorMessage {
                            tokenActivityErrorMessage = errorMessage
                        }
                    case .cost:
                        break
                    }
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
            quotaSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        return quotaSucceeded
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

    func refreshFromButton() async {
        guard !isRefreshButtonBusy else { return }
        isRefreshButtonBusy = true
        defer { isRefreshButtonBusy = false }

        _ = await refresh()
    }

    private func startTokenActivityRefreshIfNeeded() {
        guard tokenActivityTask == nil else { return }
        tokenActivityGeneration += 1
        let generation = tokenActivityGeneration
        isTokenActivityRefreshing = true

        tokenActivityTask = Task { [weak self, readTokenActivity, readTokenCost] in
            defer {
                self?.finishTokenRefresh(generation: generation)
            }
            await withTaskGroup(of: TokenRefreshResult.self) { group in
                group.addTask {
                    do {
                        return .activity(try await readTokenActivity(), nil)
                    } catch is CancellationError {
                        return .activity(nil, nil)
                    } catch {
                        return .activity(nil, error.localizedDescription)
                    }
                }
                group.addTask {
                    do {
                        return .cost(try await readTokenCost(), nil)
                    } catch is CancellationError {
                        return .cost(nil, nil)
                    } catch {
                        return .cost(nil, error.localizedDescription)
                    }
                }

                for await result in group {
                    guard let self,
                          self.tokenActivityGeneration == generation,
                          !Task.isCancelled else { return }

                    switch result {
                    case let .activity(activity, errorMessage):
                        if let activity {
                            self.tokenActivity = activity
                            self.tokenActivityErrorMessage = nil
                            self.publishTokenCost()
                        } else if let errorMessage {
                            self.tokenActivityErrorMessage = errorMessage
                        }
                    case let .cost(cost, errorMessage):
                        if let cost {
                            self.recordedTokenCost = cost
                            self.publishTokenCost()
                            self.tokenCostErrorMessage = nil
                        } else if let errorMessage {
                            self.tokenCostErrorMessage = errorMessage
                        }
                    }
                }
            }
        }
    }

    private func startTokenCostRefreshIfNeeded() {
        guard tokenActivityTask == nil else { return }
        tokenActivityGeneration += 1
        let generation = tokenActivityGeneration
        isTokenActivityRefreshing = true

        tokenActivityTask = Task { [weak self, readTokenCost] in
            defer {
                self?.finishTokenRefresh(generation: generation)
            }
            do {
                let cost = try await readTokenCost()
                guard let self,
                      self.tokenActivityGeneration == generation,
                      !Task.isCancelled else { return }
                self.recordedTokenCost = cost
                self.publishTokenCost()
                self.tokenCostErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.tokenActivityGeneration == generation,
                      !Task.isCancelled else { return }
                self.tokenCostErrorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleTokenCostRefreshFromSyncChange() {
        costSyncDebounceTask?.cancel()
        costSyncDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: costSyncChangeDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.tokenActivityTask == nil else {
                self.pendingCostSyncRefresh = true
                return
            }
            self.startTokenCostRefreshIfNeeded()
        }
    }

    private func finishTokenRefresh(generation: Int) {
        guard tokenActivityGeneration == generation else { return }
        isTokenActivityRefreshing = false
        tokenActivityTask = nil
        guard pendingCostSyncRefresh else { return }
        pendingCostSyncRefresh = false
        startTokenCostRefreshIfNeeded()
    }

    private func publishTokenCost() {
        guard let recordedTokenCost else { return }
        guard let tokenActivity else {
            tokenCost = recordedTokenCost
            return
        }
        tokenCost = TokenCostReconciler.reconcile(
            recordedTokenCost,
            with: tokenActivity
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
