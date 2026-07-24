import Darwin
import Foundation

extension Notification.Name {
    static let codexQCostSyncPreferencesDidChange = Notification.Name("codexQCostSyncPreferencesDidChange")
}

final class CostSyncFolderChangeStream: @unchecked Sendable {
    static let shared = CostSyncFolderChangeStream()

    func events() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let box = CostSyncFolderWatcherBox()
            let watcher = CostSyncFolderWatcher(continuation: continuation)
            box.watcher = watcher
            watcher.start()
            continuation.onTermination = { _ in
                box.watcher?.stop()
                box.watcher = nil
            }
        }
    }
}

private final class CostSyncFolderWatcherBox: @unchecked Sendable {
    var watcher: CostSyncFolderWatcher?
}

private final class CostSyncFolderWatcher: @unchecked Sendable {
    private let continuation: AsyncStream<Void>.Continuation
    private let queue = DispatchQueue(label: "CodexQ.CostSyncFolderWatcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var observedFolderPath: String?
    private var preferencesToken: NSObjectProtocol?

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    func start() {
        queue.async { [weak self] in
            self?.rebuildSources(yieldChange: false)
        }
        preferencesToken = NotificationCenter.default.addObserver(
            forName: .codexQCostSyncPreferencesDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            queue.async { [weak self] in
                self?.rebuildSources(yieldChange: true)
            }
        }
    }

    func stop() {
        if let preferencesToken {
            NotificationCenter.default.removeObserver(preferencesToken)
        }
        preferencesToken = nil
        queue.async { [weak self] in
            self?.cancelSources()
            self?.observedFolderPath = nil
        }
    }

    private func rebuildSources(yieldChange: Bool) {
        let folderURL = CostSyncPreferences.configuration()?.folderURL.standardizedFileURL
        let folderPath = folderURL?.path
        guard folderPath != observedFolderPath else { return }
        cancelSources()
        observedFolderPath = folderPath
        if let folderURL {
            installSources(in: folderURL)
        }
        if yieldChange {
            continuation.yield()
        }
    }

    private func installSources(in folderURL: URL) {
        for directory in watchedDirectories(root: folderURL) {
            let fd = Darwin.open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.handleFolderEvent()
            }
            source.setCancelHandler {
                Darwin.close(fd)
            }
            sources.append(source)
            source.resume()
        }
    }

    private func watchedDirectories(root: URL) -> [URL] {
        var directories = [root]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return directories
        }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            directories.append(url)
        }
        return directories
    }

    private func handleFolderEvent() {
        let folderURL = CostSyncPreferences.configuration()?.folderURL.standardizedFileURL
        cancelSources()
        observedFolderPath = folderURL?.path
        if let folderURL {
            installSources(in: folderURL)
        }
        continuation.yield()
    }

    private func cancelSources() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }
}
