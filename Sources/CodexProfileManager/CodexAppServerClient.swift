@preconcurrency import Foundation

final class CodexAppServerClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case codexNotFound
        case launchFailed
        case timedOut
        case invalidResponse(String)
        case serverError(String)
        case processExited(String)

        var errorDescription: String? {
            switch self {
            case .codexNotFound: "未找到官方 codex 命令。"
            case .launchFailed: "无法启动 codex app-server。"
            case .timedOut: "Codex 服务响应超时，请确认该账号已完成登录。"
            case .invalidResponse(let message): "Codex 服务返回无效数据：\(message)"
            case .serverError(let message):
                if message.localizedCaseInsensitiveContains("authentication required")
                    || message.localizedCaseInsensitiveContains("token_invalidated")
                    || message.localizedCaseInsensitiveContains("token_revoked")
                    || message.localizedCaseInsensitiveContains("invalidated oauth token")
                    || message.localizedCaseInsensitiveContains("authentication token has been invalidated") {
                    "该账号的 Codex 登录已失效。请点击“登录/重新登录”，完成登录后再刷新额度。"
                } else {
                    "Codex 服务错误：\(message)"
                }
            case .processExited(let message):
                "Codex 服务启动失败：\(message)"
            }
        }
    }

    private let codexExecutable: String?

    init(codexExecutable: String? = CodexExecutableLocator.locate()) {
        self.codexExecutable = codexExecutable
    }

    func fetchQuota(profile: CodexProfile) async throws -> QuotaSnapshot {
        let responses = try await request(
            profile: profile,
            requests: [
                RPCRequest(id: 2, method: "account/read", params: ["refreshToken": true]),
                RPCRequest(id: 3, method: "account/rateLimits/read", params: nil),
            ]
        )
        let accountResult = try resultObject(responses[2])
        let rateResult = try resultObject(responses[3])
        let account = accountResult["account"] as? [String: Any]
        guard let email = account?["email"] as? String, !email.isEmpty else {
            throw ClientError.invalidResponse("account/read 未返回登录邮箱")
        }
        let rateLimits = rateResult["rateLimits"] as? [String: Any] ?? [:]

        return QuotaSnapshot(
            email: email,
            planType: (account?["planType"] as? String) ?? (rateLimits["planType"] as? String),
            primary: decodeWindow(rateLimits["primary"]),
            secondary: decodeWindow(rateLimits["secondary"]),
            credits: decodeCredits(rateLimits["credits"]),
            fetchedAt: Date(),
            stale: false,
            errorMessage: nil
        )
    }

    func validateAuthentication(profile: CodexProfile) async throws -> String? {
        let responses = try await request(
            profile: profile,
            requests: [
                RPCRequest(id: 2, method: "account/read", params: ["refreshToken": true])
            ]
        )
        let result = try resultObject(responses[2])
        let account = result["account"] as? [String: Any]
        guard let email = account?["email"] as? String, !email.isEmpty else {
            throw ClientError.invalidResponse("account/read 未返回登录邮箱")
        }
        return email
    }

    func recentThreads(profile: CodexProfile, limit: Int = 10) async throws -> [ThreadSummary] {
        let responses = try await request(
            profile: profile,
            requests: [
                RPCRequest(id: 2, method: "thread/list", params: [
                    "limit": limit,
                    "sortKey": "updated_at",
                    "sortDirection": "desc",
                    "useStateDbOnly": true,
                ])
            ]
        )
        let result = try resultObject(responses[2])
        let items = result["data"] as? [[String: Any]] ?? []
        return items.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return ThreadSummary(
                id: id,
                cwd: $0["cwd"] as? String,
                title: $0["name"] as? String ?? $0["title"] as? String,
                status: ($0["status"] as? [String: Any])?["type"] as? String ?? $0["status"] as? String
            )
        }
    }

    private func request(profile: CodexProfile, requests: [RPCRequest]) async throws -> [Int: Data] {
        guard let codexExecutable,
              FileManager.default.isExecutableFile(atPath: codexExecutable) else { throw ClientError.codexNotFound }

        return try await withCheckedThrowingContinuation { continuation in
            let startedAt = Date()
            let requestMethods = requests.map(\.method).joined(separator: ",")
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: codexExecutable)
            process.arguments = ["app-server", "--stdio"]
            process.environment = CodexRuntimeEnvironment.environment(
                codexHome: profile.codexHome,
                codexExecutable: codexExecutable
            )
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors

            let state = AppServerProcessState(expected: Set([1] + requests.map(\.id)), process: process)

            let finish: @Sendable (Result<[Int: Data], Error>) -> Void = { result in
                guard state.markFinished() else { return }
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                if process.isRunning { process.terminate() }
                let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
                switch result {
                case .success:
                    OperationLogger.info(
                        "appServer.request.completed",
                        profile: profile,
                        message: "Codex app-server request completed",
                        metadata: ["methods": requestMethods],
                        durationMs: durationMs
                    )
                case .failure(let error):
                    OperationLogger.error(
                        "appServer.request.failed",
                        profile: profile,
                        message: "Codex app-server request failed",
                        metadata: ["methods": requestMethods],
                        durationMs: durationMs,
                        error: error
                    )
                }
                continuation.resume(with: result)
            }

            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let completed = state.consume(data) { finish(.success(completed)) }
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.consumeError(data)
            }
            process.terminationHandler = { terminatedProcess in
                let detail = state.errorText.isEmpty
                    ? "进程在返回完整响应前退出，退出码 \(terminatedProcess.terminationStatus)"
                    : state.errorText
                finish(.failure(ClientError.processExited(detail)))
            }

            do {
                OperationLogger.info(
                    "appServer.request.started",
                    profile: profile,
                    message: "Starting Codex app-server request",
                    metadata: ["methods": requestMethods, "codexHome": profile.codexHome]
                )
                try process.run()
                let initialize = RPCRequest(
                    id: 1,
                    method: "initialize",
                    params: [
                        "clientInfo": ["name": "codex-profile-manager", "version": "0.3.7"],
                        "capabilities": ["experimentalApi": true],
                    ]
                )
                for request in [initialize] + requests {
                    let data = try JSONSerialization.data(withJSONObject: request.jsonObject)
                    try input.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
                    if request.id == initialize.id {
                        let initialized = ["method": "initialized", "params": [:]] as [String: Any]
                        let initializedData = try JSONSerialization.data(withJSONObject: initialized)
                        try input.fileHandleForWriting.write(contentsOf: initializedData + Data("\n".utf8))
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                    finish(.failure(ClientError.timedOut))
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func resultObject(_ responseData: Data?) throws -> [String: Any] {
        guard let responseData,
              let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ClientError.invalidResponse("missing response")
        }
        if let error = response["error"] as? [String: Any] {
            throw ClientError.serverError(error["message"] as? String ?? "unknown error")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw ClientError.invalidResponse("missing result")
        }
        return result
    }

    private func decodeWindow(_ value: Any?) -> RateLimitWindow? {
        guard let object = value as? [String: Any], let used = object["usedPercent"] as? Int else { return nil }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMins: object["windowDurationMins"] as? Int,
            resetsAt: object["resetsAt"] as? Int
        )
    }

    private func decodeCredits(_ value: Any?) -> CreditsSnapshot? {
        guard let object = value as? [String: Any] else { return nil }
        return CreditsSnapshot(
            hasCredits: object["hasCredits"] as? Bool ?? false,
            unlimited: object["unlimited"] as? Bool ?? false,
            balance: object["balance"] as? String
        )
    }
}

private struct RPCRequest {
    let id: Int
    let method: String
    let params: Any?

    var jsonObject: [String: Any] {
        ["id": id, "method": method, "params": params ?? NSNull()]
    }
}

private final class AppServerProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private let expected: Set<Int>
    private let process: Process
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var errorBuffer = Data()
    private var finished = false

    init(expected: Set<Int>, process: Process) {
        self.expected = expected
        self.process = process
    }

    func consume(_ data: Data) -> [Int: Data]? {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newline.lowerBound)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                let id = (object["id"] as? Int) ?? (object["id"] as? NSNumber)?.intValue
                if let id {
                    responses[id] = line
                }
            }
        }
        return expected.isSubset(of: responses.keys) ? responses : nil
    }

    func consumeError(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        errorBuffer.append(data)
        if errorBuffer.count > 16_384 {
            errorBuffer = errorBuffer.suffix(16_384)
        }
    }

    var errorText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: errorBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}
