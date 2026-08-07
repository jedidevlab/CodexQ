import AppKit
import SwiftUI

@MainActor
final class TokenHistoryWindowController: NSWindowController {
    private let historyStore: TokenHistoryStore

    init(store: TokenHistoryStore = TokenHistoryStore()) {
        historyStore = store
        let hostingController = NSHostingController(rootView: TokenHistoryView(store: store))
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Token 使用与成本"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 840, height: 600)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.setFrameAutosaveName("TokenHistoryWindow")
        let restoredSize = window.frame.size
        if restoredSize.width < window.minSize.width || restoredSize.height < window.minSize.height {
            var restoredFrame = window.frame
            restoredFrame.origin.y -= max(0, window.minSize.height - restoredSize.height)
            restoredFrame.size = NSSize(
                width: max(restoredSize.width, window.minSize.width),
                height: max(restoredSize.height, window.minSize.height)
            )
            window.setFrame(restoredFrame, display: false)
        }
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
