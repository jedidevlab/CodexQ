import Foundation
import ServiceManagement

enum QuotaWarningThresholds {
    static let customRange = 1...99

    static func clamped(_ value: Int) -> Int {
        Swift.min(customRange.upperBound, Swift.max(customRange.lowerBound, value))
    }

    static func resolved(
        notifyAt20: Bool,
        notifyAt10: Bool,
        notifyAt5: Bool,
        notifyAtCustom: Bool,
        customThreshold: Int
    ) -> [Int] {
        var thresholds = Set(
            [(20, notifyAt20), (10, notifyAt10), (5, notifyAt5)]
                .compactMap { $0.1 ? $0.0 : nil }
        )
        if notifyAtCustom {
            thresholds.insert(clamped(customThreshold))
        }
        return thresholds.sorted(by: >)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    @Published var notifyAt20: Bool { didSet { defaults.set(notifyAt20, forKey: Keys.notifyAt20) } }
    @Published var notifyAt10: Bool { didSet { defaults.set(notifyAt10, forKey: Keys.notifyAt10) } }
    @Published var notifyAt5: Bool { didSet { defaults.set(notifyAt5, forKey: Keys.notifyAt5) } }
    @Published var notifyAtCustom: Bool {
        didSet { defaults.set(notifyAtCustom, forKey: Keys.notifyAtCustom) }
    }
    @Published private(set) var customWarningThreshold: Int
    @Published private(set) var notificationPermissionWarning: String?
    @Published private(set) var icloudCostSyncEnabled: Bool
    @Published private(set) var icloudCostSyncFolderPath: String?
    @Published private(set) var icloudCostSyncSetupError: String?
    var warningThresholds: [Int] {
        QuotaWarningThresholds.resolved(
            notifyAt20: notifyAt20,
            notifyAt10: notifyAt10,
            notifyAt5: notifyAt5,
            notifyAtCustom: notifyAtCustom,
            customThreshold: customWarningThreshold
        )
    }
    private let defaults = UserDefaults.standard
    private var isUpdatingLaunchAtLogin = false

    private enum Keys {
        static let legacySettingsMigrated = "legacySettingsMigrated"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyAt20 = "notifyAt20"
        static let notifyAt10 = "notifyAt10"
        static let notifyAt5 = "notifyAt5"
        static let notifyAtCustom = "notifyAtCustom"
        static let customWarningThreshold = "customWarningThreshold"
    }

    private init() {
        Self.migrateLegacySettingsIfNeeded(to: defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        notifyAt20 = defaults.object(forKey: Keys.notifyAt20) as? Bool ?? true
        notifyAt10 = defaults.object(forKey: Keys.notifyAt10) as? Bool ?? true
        notifyAt5 = defaults.object(forKey: Keys.notifyAt5) as? Bool ?? true
        notifyAtCustom = defaults.bool(forKey: Keys.notifyAtCustom)
        customWarningThreshold = QuotaWarningThresholds.clamped(
            defaults.object(forKey: Keys.customWarningThreshold) as? Int ?? 15
        )
        notificationPermissionWarning = nil
        icloudCostSyncEnabled = defaults.bool(forKey: CostSyncPreferences.enabledKey)
        icloudCostSyncFolderPath = defaults.string(forKey: CostSyncPreferences.folderPathKey)
        icloudCostSyncSetupError = nil
    }

    func setCustomWarningThreshold(_ threshold: Int) {
        customWarningThreshold = QuotaWarningThresholds.clamped(threshold)
        defaults.set(customWarningThreshold, forKey: Keys.customWarningThreshold)
    }

    var icloudCostSyncFolderName: String? {
        icloudCostSyncFolderPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).lastPathComponent
        }
    }

    func enableICloudCostSync(folderURL: URL) async throws {
        do {
            let namespace = try await Task.detached {
                try CostLedgerSyncService().prepare(folderURL: folderURL)
            }.value
            if defaults.string(forKey: CostSyncPreferences.deviceIDKey) == nil {
                defaults.set(UUID().uuidString, forKey: CostSyncPreferences.deviceIDKey)
            }
            let path = folderURL.standardizedFileURL.path
            defaults.set(path, forKey: CostSyncPreferences.folderPathKey)
            defaults.set(namespace, forKey: CostSyncPreferences.namespaceKey)
            defaults.set(true, forKey: CostSyncPreferences.enabledKey)
            icloudCostSyncFolderPath = path
            icloudCostSyncEnabled = true
            icloudCostSyncSetupError = nil
            NotificationCenter.default.post(name: .codexQCostSyncPreferencesDidChange, object: nil)
        } catch {
            icloudCostSyncSetupError = error.localizedDescription
            throw error
        }
    }

    func disableICloudCostSync() {
        defaults.set(false, forKey: CostSyncPreferences.enabledKey)
        icloudCostSyncEnabled = false
        icloudCostSyncSetupError = nil
        NotificationCenter.default.post(name: .codexQCostSyncPreferencesDidChange, object: nil)
    }

    func updateNotificationPermissionWarning(authorizationGranted: Bool) {
        notificationPermissionWarning = authorizationGranted
            ? nil
            : "系统通知未允许，请在“系统设置 > 通知”中允许 CodexQ 通知。"
    }

    private static func migrateLegacySettingsIfNeeded(to defaults: UserDefaults) {
        guard !defaults.bool(forKey: Keys.legacySettingsMigrated),
              let legacyDefaults = UserDefaults(suiteName: "com.jun.codesk") else {
            return
        }

        for key in [
            Keys.notificationsEnabled,
            Keys.notifyAt20,
            Keys.notifyAt10,
            Keys.notifyAt5
        ] where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: Keys.legacySettingsMigrated)
    }

    private func updateLaunchAtLogin() {
        guard !isUpdatingLaunchAtLogin else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isUpdatingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isUpdatingLaunchAtLogin = false
        }
    }
}
