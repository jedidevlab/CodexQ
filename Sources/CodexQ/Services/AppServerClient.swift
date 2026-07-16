import Darwin
import Foundation

struct AppServerClient: Sendable {
    enum ClientError: LocalizedError {
        case executableMissing
        case launchFailed(String)
        case serverClosed
        case responseTimedOut
        case serverError(String)
        case missingRateLimits
        case missingTokenActivity

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                return "未找到 ChatGPT/Codex app-server"
            case .launchFailed(let message):
                return "无法启动 Codex app-server：\(message)"
            case .serverClosed:
                return "Codex app-server 意外关闭"
            case .responseTimedOut:
                return "Codex app-server 响应超时"
            case .serverError(let message):
                return "Codex app-server 返回错误：\(message)"
            case .missingRateLimits:
                return "额度响应缺少 5 小时或周限额"
            case .missingTokenActivity:
                return "用量响应缺少 token 活动数据"
            }
        }
    }

    static var defaultExecutableURLs: [URL] {
        defaultExecutableURLs(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func defaultExecutableURLs(homeDirectory: URL) -> [URL] {
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        return ["ChatGPT", "Codex"].flatMap { appName in
            applicationDirectories.map {
                $0.appendingPathComponent("\(appName).app/Contents/Resources/codex")
            }
        }
    }

    private let executableURLs: [URL]
    private let responseTimeout: TimeInterval

    init(
        executableURL: URL? = nil,
        responseTimeout: TimeInterval = 10
    ) {
        executableURLs = executableURL.map { [$0] } ?? Self.defaultExecutableURLs
        self.responseTimeout = responseTimeout
    }

    static func firstExecutableURL(
        in candidates: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    func readRateLimits() async throws -> QuotaSnapshot {
        try await Task.detached(priority: .utility) {
            try readRateLimitsSynchronously()
        }.value
    }

    func readTokenActivity() async throws -> TokenActivitySnapshot {
        try await Task.detached(priority: .utility) {
            try readTokenActivitySynchronously()
        }.value
    }

    private func readRateLimitsSynchronously() throws -> QuotaSnapshot {
        guard let result = try readResult(method: "account/rateLimits/read") else {
            throw ClientError.serverError("未知错误")
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        let decoded = try JSONDecoder().decode(RateLimitsResponse.self, from: data)

        guard let snapshot = decoded.quotaSnapshot else {
            throw ClientError.missingRateLimits
        }
        return snapshot
    }

    private func readTokenActivitySynchronously() throws -> TokenActivitySnapshot {
        guard let result = try readResult(method: "account/usage/read") else {
            throw ClientError.missingTokenActivity
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)
    }

    private func readResult(method: String) throws -> Any? {
        guard let executableURL = Self.firstExecutableURL(in: executableURLs) else {
            throw ClientError.executableMissing
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }

        defer {
            inputPipe.fileHandleForWriting.closeFile()
            stop(process)
        }

        try write(
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codexq",
                        "title": "CodexQ",
                        "version": "1.0.0"
                    ],
                    "capabilities": [
                        "experimentalApi": true,
                        "requestAttestation": false
                    ]
                ]
            ],
            to: inputPipe.fileHandleForWriting
        )
        let initializeResponse = try readResponse(id: 1, from: outputPipe.fileHandleForReading)
        try validate(initializeResponse)

        try write(["method": "initialized"], to: inputPipe.fileHandleForWriting)
        try write(
            ["method": method, "id": 2],
            to: inputPipe.fileHandleForWriting
        )

        let response = try readResponse(id: 2, from: outputPipe.fileHandleForReading)
        try validate(response)
        return response["result"]
    }

    private func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func readResponse(
        id expectedID: Int,
        from handle: FileHandle
    ) throws -> [String: Any] {
        var buffer = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + responseTimeout

        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                throw ClientError.responseTimedOut
            }

            var descriptor = pollfd(
                fd: handle.fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
            let pollResult = Darwin.poll(
                &descriptor,
                1,
                Int32(min(remaining * 1_000, Double(Int32.max)))
            )

            if pollResult == 0 {
                throw ClientError.responseTimedOut
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw ClientError.serverClosed
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                throw ClientError.serverClosed
            }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? NSNumber)?.intValue == expectedID else {
                    continue
                }
                return object
            }
        }
    }

    private func validate(_ response: [String: Any]) throws {
        guard let error = response["error"] else { return }

        if let errorObject = error as? [String: Any],
           let message = errorObject["message"] as? String {
            throw ClientError.serverError(message)
        }
        throw ClientError.serverError(String(describing: error))
    }

    private func stop(_ process: Process) {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }

        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
        }

        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
