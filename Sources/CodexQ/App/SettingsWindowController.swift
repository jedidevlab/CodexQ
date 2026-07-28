import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: QuotaStore, settings: AppSettings) {
        let hostingController = NSHostingController(
            rootView: SettingsWindowView(store: store, settings: settings)
        )
        let contentSize = hostingController.sizeThatFits(
            in: NSSize(width: 380, height: 600)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexQ 设置"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
