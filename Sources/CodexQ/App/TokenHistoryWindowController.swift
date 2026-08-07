import AppKit
import SwiftUI

@MainActor
final class TokenHistoryWindowController: NSWindowController {
    private let historyStore: TokenHistoryStore

    init(store: TokenHistoryStore = TokenHistoryStore()) {
        historyStore = store
        let hostingController = NSHostingController(rootView: TokenHistoryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Token 使用与成本"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.setFrameAutosaveName("TokenHistoryWindow")
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
        historyStore.loadIfNeeded()
    }
}
