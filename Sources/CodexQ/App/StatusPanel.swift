import AppKit

@MainActor
final class StatusPanel: NSPanel {
    var didClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !self.isKeyWindow, self.isVisible else { return }
            self.orderOut(nil)
        }
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible {
            didClose?()
        }
    }
}
