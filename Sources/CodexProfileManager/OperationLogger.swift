import Foundation

enum OperationLogger {
    private static let lock = NSLock()
    private static let maximumLogSize = 5 * 1_024 * 1_024
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func info(
        _ event: String,
        profile: CodexProfile? = nil,
        message: String,
        metadata: [String: String] = [:],
        durationMs: Int? = nil
    ) {
        append(.init(
            level: .info,
            event: event,
            profileID: profile?.id,
            profileName: profile?.displayName,
            message: message,
            metadata: sanitized(metadata),
            durationMs: durationMs,
            errorMessage: nil
        ))
    }

    static func warning(
        _ event: String,
        profile: CodexProfile? = nil,
        message: String,
        metadata: [String: String] = [:],
        durationMs: Int? = nil,
        error: Error? = nil
    ) {
        append(.init(
            level: .warning,
            event: event,
            profileID: profile?.id,
            profileName: profile?.displayName,
            message: message,
            metadata: sanitized(metadata),
            durationMs: durationMs,
            errorMessage: error?.localizedDescription
        ))
    }

    static func error(
        _ event: String,
        profile: CodexProfile? = nil,
        message: String,
        metadata: [String: String] = [:],
        durationMs: Int? = nil,
        error: Error
    ) {
        append(.init(
            level: .error,
            event: event,
            profileID: profile?.id,
            profileName: profile?.displayName,
            message: message,
            metadata: sanitized(metadata),
            durationMs: durationMs,
            errorMessage: error.localizedDescription
        ))
    }

    static func recent(limit: Int = 300) -> [OperationLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let data = [AppPaths.previousOperationLogFile, AppPaths.operationLogFile]
            .compactMap { try? Data(contentsOf: $0) }
            .reduce(into: Data()) { $0.append($1) }
        guard !data.isEmpty else { return [] }
        return Array(jsonObjects(in: data)
            .suffix(limit)
            .compactMap { try? AtomicJSONStore.decoder.decode(OperationLogEntry.self, from: $0) }
            .reversed())
    }

    private static func append(_ entry: OperationLogEntry) {
        if ProcessInfo.processInfo.environment["CODEX_PROFILE_MANAGER_DISABLE_LOGS"] == "1" {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        do {
            try AppPaths.ensureDirectories()
            try rotateIfNeeded()
            let data = try encoder.encode(entry) + Data("\n".utf8)
            if FileManager.default.fileExists(atPath: AppPaths.operationLogFile.path) {
                let handle = try FileHandle(forWritingTo: AppPaths.operationLogFile)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: AppPaths.operationLogFile, options: .atomic)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.operationLogFile.path)
        } catch {
            NSLog("CodexProfileManager log write failed: \(error.localizedDescription)")
        }
    }

    private static func rotateIfNeeded() throws {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: AppPaths.operationLogFile.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size >= maximumLogSize else { return }
        if fileManager.fileExists(atPath: AppPaths.previousOperationLogFile.path) {
            try fileManager.removeItem(at: AppPaths.previousOperationLogFile)
        }
        try fileManager.moveItem(at: AppPaths.operationLogFile, to: AppPaths.previousOperationLogFile)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.previousOperationLogFile.path)
    }

    private static func sanitized(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { result, pair in
            let key = pair.key.lowercased()
            if key.contains("token") || key.contains("secret") || key.contains("auth") {
                result[pair.key] = "<redacted>"
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    // Supports both current one-line JSONL and older pretty-printed entries.
    private static func jsonObjects(in data: Data) -> [Data] {
        var results: [Data] = []
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false

        for (index, byte) in data.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                if depth == 0 { start = index }
                depth += 1
            } else if byte == 0x7D, depth > 0 {
                depth -= 1
                if depth == 0, let startIndex = start {
                    results.append(data.subdata(in: startIndex..<(index + 1)))
                    start = nil
                }
            }
        }
        return results
    }
}
