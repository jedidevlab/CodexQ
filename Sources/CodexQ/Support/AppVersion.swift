import Foundation

enum AppVersion {
    static var current: String {
        if let bundleVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }

        for bundle in [Bundle.main, Bundle.module] {
            guard let url = bundle.url(forResource: "Version", withExtension: "txt"),
                  let value = try? String(contentsOf: url, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return "0.0.0"
    }
}
