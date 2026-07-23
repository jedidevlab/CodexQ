import Darwin
import Foundation

struct AppServerSnapshots: Sendable {
    let quota: QuotaSnapshot
    let tokenActivity: TokenActivitySnapshot
}

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
    private let environment: [String: String]
    private let readResetCreditDetails: @Sendable () async throws -> ResetCreditsSummary?

    init(
        executableURL: URL? = nil,
        responseTimeout: TimeInterval = 10,
        environment: [String: String] = [:],
        readResetCreditDetails: (@Sendable () async throws -> ResetCreditsSummary?)? = nil
    ) {
        executableURLs = executableURL.map { [$0] } ?? Self.defaultExecutableURLs
        self.responseTimeout = responseTimeout
        self.environment = environment
        self.readResetCreditDetails = readResetCreditDetails ?? {
            try await ResetCreditDetailsClient().read()
        }
    }

    static func firstExecutableURL(
        in candidates: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func shouldReadResetCreditDetails(for summary: ResetCreditsSummary?) -> Bool {
        guard let summary, summary.availableCount > 0 else { return false }
        return summary.availableCredits.isEmpty
    }

    func readRateLimits() async throws -> QuotaSnapshot {
        let snapshot = try await runSynchronously {
            try readRateLimitsSynchronously()
        }
        guard Self.shouldReadResetCreditDetails(for: snapshot.resetCredits),
              let details = try? await readResetCreditDetails() else {
            return snapshot
        }
        return QuotaSnapshot(
            fiveHour: snapshot.fiveHour,
            weekly: snapshot.weekly,
            resetCredits: details,
            planType: snapshot.planType
        )
    }

    func readTokenActivity() async throws -> TokenActivitySnapshot {
        try await runSynchronously {
            try readTokenActivitySynchronously()
        }
    }

    func readDashboardSnapshots() async throws -> AppServerSnapshots {
        try await runSynchronously {
            try readDashboardSnapshotsSynchronously()
        }
    }

    private func runSynchronously<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func readRateLimitsSynchronously() throws -> QuotaSnapshot {
        guard let result = try readResults(methods: ["account/rateLimits/read"])["account/rateLimits/read"] else {
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
        guard let result = try readResults(methods: ["account/usage/read"])["account/usage/read"] else {
            throw ClientError.missingTokenActivity
        }

        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(TokenActivitySnapshot.self, from: data)
    }

    private func readDashboardSnapshotsSynchronously() throws -> AppServerSnapshots {
        let results = try readResults(methods: [
            "account/rateLimits/read",
            "account/usage/read"
        ])
        guard let rateLimitsResult = results["account/rateLimits/read"] else {
            throw ClientError.serverError("未知错误")
        }
        guard let usageResult = results["account/usage/read"] else {
            throw ClientError.missingTokenActivity
        }

        let rateLimitsData = try JSONSerialization.data(withJSONObject: rateLimitsResult)
        let usageData = try JSONSerialization.data(withJSONObject: usageResult)
        let decodedRateLimits = try JSONDecoder().decode(RateLimitsResponse.self, from: rateLimitsData)
        let tokenActivity = try JSONDecoder().decode(TokenActivitySnapshot.self, from: usageData)
        guard let quota = decodedRateLimits.quotaSnapshot else {
            throw ClientError.missingRateLimits
        }
        return AppServerSnapshots(quota: quota, tokenActivity: tokenActivity)
    }

    private func readResults(methods: [String]) throws -> [String: Any] {
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
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

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
                        "version": AppVersion.current
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
        var results: [String: Any] = [:]
        for (index, method) in methods.enumerated() {
            let id = index + 2
            try write(
                ["method": method, "id": id],
                to: inputPipe.fileHandleForWriting
            )

            let response = try readResponse(id: id, from: outputPipe.fileHandleForReading)
            try validate(response)
            if let result = response["result"] {
                results[method] = result
            }
        }
        return results
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
            try Task.checkCancellation()
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
                Int32(min(remaining * 1_000, 100))
            )

            if pollResult == 0 { continue }
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

struct ResetCreditDetailsClient {
    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let accountID: String?
            let idToken: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountID = "account_id"
                case idToken = "id_token"
            }
        }

        let tokens: Tokens
    }

    private struct IDTokenClaims: Decodable {
        struct AuthClaims: Decodable {
            let isFedRAMP: Bool?

            enum CodingKeys: String, CodingKey {
                case isFedRAMP = "chatgpt_account_is_fedramp"
            }
        }

        let auth: AuthClaims?

        enum CodingKeys: String, CodingKey {
            case auth = "https://api.openai.com/auth"
        }
    }

    static func makeRequest(authData: Data) throws -> URLRequest {
        let tokens = try JSONDecoder().decode(AuthFile.self, from: authData).tokens

        var request = URLRequest(
            url: URL(string:
                "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
            )!
        )
        request.setValue(
            "Bearer \(tokens.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(tokens.accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        if isFedRAMP(idToken: tokens.idToken) {
            request.setValue("true", forHTTPHeaderField: "X-OpenAI-Fedramp")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5
        return request
    }

    private static func isFedRAMP(idToken: String?) -> Bool {
        guard let payload = idToken?.split(separator: ".").dropFirst().first else {
            return false
        }
        var base64 = String(payload)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONDecoder().decode(IDTokenClaims.self, from: data) else {
            return false
        }
        return claims.auth?.isFedRAMP == true
    }

    func read() async throws -> ResetCreditsSummary {
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        let authData = try Data(contentsOf: authURL)
        let request = try Self.makeRequest(authData: authData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder()
            .decode(RateLimitResetCreditDetailsResponse.self, from: data)
            .summary
    }
}
