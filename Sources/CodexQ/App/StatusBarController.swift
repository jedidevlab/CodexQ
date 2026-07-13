import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = StatusPanel(
        contentRect: NSRect(x: 0, y: 0, width: 316, height: 250),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let store = QuotaStore()
    private let sourceIcon: NSImage
    private var hostingController: NSHostingController<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var autoCloseTask: Task<Void, Never>?
    private var freshnessTask: Task<Void, Never>?
    private var panelRefitTask: Task<Void, Never>?
    private var currentAnchorRect: NSRect?
    private var currentVisibleFrame: NSRect?

    override init() {
        let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
        guard let url = iconURL, let image = NSImage(contentsOf: url) else {
            fatalError("Missing MenuBarIcon.png")
        }
        sourceIcon = image
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        let rootView = AnyView(
            QuotaPopoverView(
                store: store,
                settings: .shared
            ) { [weak self] in
                self?.schedulePanelRefit()
                self?.scheduleAutoClose()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.separator.opacity(0.7), lineWidth: 1)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        panel.contentViewController = hostingController
        panel.didClose = { [weak self] in
            self?.panelDidClose()
        }

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.imagePosition = .imageLeading
        }

        store.$snapshot
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$isRefreshing
            .removeDuplicates()
            .sink { [weak self] isRefreshing in
                self?.updateAutoClose(isRefreshing: isRefreshing)
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$errorMessage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$tokenActivity
            .sink { [weak self] _ in
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$tokenActivityErrorMessage
            .sink { [weak self] _ in
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$isTokenActivityRefreshing
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.schedulePanelRefit()
            }
            .store(in: &cancellables)

        store.$lastUpdatedAt
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        store.start()
        freshnessTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.updateStatusItem()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            store.setPopoverPresented(true)
            let anchorRect = button.window?.convertToScreen(
                button.convert(StatusPopoverAnchor.rect(for: button), to: nil)
            )
            guard let anchorRect,
                  let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) })
                    ?? button.window?.screen else {
                return
            }
            currentAnchorRect = anchorRect
            currentVisibleFrame = screen.visibleFrame
            fitPanel(anchorRect: anchorRect, visibleFrame: screen.visibleFrame)
            panel.orderFrontRegardless()
            panel.makeKey()
            updateAutoClose(isRefreshing: store.isRefreshing)
            Task { [weak store] in
                await store?.refreshIfNeededOnPresentation()
            }
        }
    }

    private func panelDidClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        store.setPopoverPresented(false)
    }

    func stop() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
        freshnessTask?.cancel()
        freshnessTask = nil
        panelRefitTask?.cancel()
        panelRefitTask = nil
        panel.orderOut(nil)
        store.stop()
    }

    private func scheduleAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            self?.panel.orderOut(nil)
        }
    }

    private func updateAutoClose(isRefreshing: Bool) {
        guard panel.isVisible else { return }

        if isRefreshing {
            autoCloseTask?.cancel()
            autoCloseTask = nil
        } else {
            scheduleAutoClose()
        }
    }

    private func schedulePanelRefit() {
        guard panel.isVisible else { return }
        panelRefitTask?.cancel()
        panelRefitTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.panel.isVisible,
                  let anchorRect = self.currentAnchorRect,
                  let visibleFrame = self.currentVisibleFrame else {
                return
            }
            self.fitPanel(anchorRect: anchorRect, visibleFrame: visibleFrame)
        }
    }

    private func fitPanel(anchorRect: NSRect, visibleFrame: NSRect) {
        guard let hostingController else { return }
        let contentSize = hostingController.sizeThatFits(in: NSSize(
            width: 316,
            height: visibleFrame.height
        ))
        let fittedSize = StatusPanelPositioner.fittedSize(
            contentSize: contentSize,
            visibleFrame: visibleFrame
        )
        panel.setFrame(
            StatusPanelPositioner.frame(
                panelSize: fittedSize,
                anchorRect: anchorRect,
                visibleFrame: visibleFrame
            ),
            display: panel.isVisible
        )
    }

    private func updateStatusItem() {
        let remainingPercent = store.snapshot?.statusRemainingPercent
        let error = store.errorMessage
        let now = Date()
        let hasFreshQuota = StatusTitleFormatter.hasFreshQuota(
            remainingPercent: remainingPercent,
            lastUpdatedAt: store.lastUpdatedAt,
            now: now
        )

        statusItem.button?.image = StatusIconRenderer.image(
            source: sourceIcon,
            remainingPercent: remainingPercent ?? 100
        )
        statusItem.button?.title = StatusTitleFormatter.string(
            remainingPercent: remainingPercent,
            lastUpdatedAt: store.lastUpdatedAt,
            error: error,
            now: now
        )
        statusItem.button?.alphaValue = hasFreshQuota ? 1 : 0.55
        statusItem.button?.toolTip = StatusTitleFormatter.toolTip(
            remainingPercent: remainingPercent,
            lastUpdatedAt: store.lastUpdatedAt,
            error: error,
            now: now
        )
    }
}
