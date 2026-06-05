import Foundation

enum AppPaths {
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_PROFILE_MANAGER_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexProfileManager", isDirectory: true)
    }

    static var profilesRoot: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    static var handoffsRoot: URL { root.appendingPathComponent("Handoffs", isDirectory: true) }
    static var sharedCodexHome: URL { root.appendingPathComponent("SharedCodexHome", isDirectory: true) }
    static var partialSharedRoot: URL { root.appendingPathComponent("PartialSharedState", isDirectory: true) }
    static var profilesFile: URL { root.appendingPathComponent("profiles.json") }
    static var quotaFile: URL { root.appendingPathComponent("quota-cache.json") }
    static var auditFile: URL { root.appendingPathComponent("audit.jsonl") }
    static var operationLogFile: URL { root.appendingPathComponent("operations.jsonl") }
    static var previousOperationLogFile: URL { root.appendingPathComponent("operations.previous.jsonl") }

    static func ensureDirectories() throws {
        for directory in [root, profilesRoot, handoffsRoot, sharedCodexHome, partialSharedRoot] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    static func defaultCodexHome(profileID: UUID) -> URL {
        profilesRoot.appendingPathComponent(profileID.uuidString, isDirectory: true)
    }
}

struct CodexStatePaths {
    var root: URL
    var sharedCodexHome: URL
    var partialSharedRoot: URL

    static var live: CodexStatePaths {
        CodexStatePaths(
            root: AppPaths.root,
            sharedCodexHome: AppPaths.sharedCodexHome,
            partialSharedRoot: AppPaths.partialSharedRoot
        )
    }

    static func temporary(root: URL) -> CodexStatePaths {
        CodexStatePaths(
            root: root,
            sharedCodexHome: root.appendingPathComponent("SharedCodexHome", isDirectory: true),
            partialSharedRoot: root.appendingPathComponent("PartialSharedState", isDirectory: true)
        )
    }

    func ensureDirectories() throws {
        for directory in [root, sharedCodexHome, partialSharedRoot] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }
}

enum CodexExecutableLocator {
    static func locate() -> String? {
        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let candidates = environmentPaths.map { "\($0)/codex" } + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

enum CodexRuntimeEnvironment {
    static func environment(codexHome: String, codexExecutable: String? = nil) -> [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "CODEX_HOME": codexHome,
            "PATH": runtimePath(codexExecutable: codexExecutable),
        ]) { _, new in new }
    }

    static func shellExports(codexHome: String, codexExecutable: String? = nil) -> String {
        "export CODEX_HOME=\(shellQuote(codexHome)); export PATH=\(shellQuote(runtimePath(codexExecutable: codexExecutable)))"
    }

    static func runtimePath(codexExecutable: String? = nil) -> String {
        var paths: [String] = []
        if let existing = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: existing.split(separator: ":").map(String.init))
        }
        if let codexExecutable {
            paths.append(URL(fileURLWithPath: codexExecutable).deletingLastPathComponent().path)
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])
        paths.append(contentsOf: nvmNodePaths())
        return uniqueExistingDirectories(paths).joined(separator: ":")
    }

    private static func nvmNodePaths() -> [String] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let versions = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return versions
            .map { $0.appendingPathComponent("bin", isDirectory: true).path }
            .sorted(by: >)
    }

    private static func uniqueExistingDirectories(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
