import AppKit
import CoreGraphics

enum ScreenSessionState {
    static func isLocked(_ session: [String: Any]?) -> Bool {
        session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

@main
enum CodexQApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            self?.startStatusControllerIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        statusController?.stop()
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        startStatusControllerIfNeeded()
    }

    private func startStatusControllerIfNeeded() {
        guard statusController == nil,
              !ScreenSessionState.isLocked(
                CGSessionCopyCurrentDictionary() as? [String: Any]
              ) else {
            return
        }
        statusController = StatusBarController()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
