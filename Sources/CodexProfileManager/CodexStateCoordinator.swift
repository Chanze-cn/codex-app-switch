import Foundation

struct CodexLaunchContext {
    let codexHome: String
    let mode: CodexSwitchMode
}

struct CodexSwitchDryRunResult {
    let context: CodexLaunchContext
    let temporaryRoot: URL
    let targetCodexHome: String
    let preservesLocalThreads: Bool
    let warnings: [String]
}

struct CodexStateCoordinator {
    enum StateError: LocalizedError {
        case missingTargetAuth

        var errorDescription: String? {
            switch self {
            case .missingTargetAuth:
                "目标账号还没有可用的 auth.json。请先完成登录后再切换。"
            }
        }
    }

    private let fileManager = FileManager.default
    private let paths: CodexStatePaths
    private let sharedFileNames: Set<String> = [
        "config.toml",
        "AGENTS.md",
        "AGENTS.override.md",
        "models_cache.json",
    ]
    private let sharedDirectoryNames: Set<String> = [
        "skills",
        "plugins",
        "prompts",
        "themes",
        "rules",
        "mcp",
        "hooks",
    ]

    init(paths: CodexStatePaths = .live) {
        self.paths = paths
    }

    func prepareForSwitch(
        previous: CodexProfile?,
        previousMode: CodexSwitchMode,
        target: CodexProfile,
        targetMode: CodexSwitchMode,
        initializeSharedFromPrevious: Bool
    ) throws -> CodexLaunchContext {
        OperationLogger.info(
            "state.prepare.started",
            profile: target,
            message: "Preparing Codex state",
            metadata: [
                "targetMode": targetMode.rawValue,
                "previousMode": previousMode.rawValue,
                "initializeSharedFromPrevious": "\(initializeSharedFromPrevious)",
            ]
        )
        try paths.ensureDirectories()
        if let previous {
            try captureStateIfNeeded(from: previous, mode: previousMode)
        }

        switch targetMode {
        case .isolated:
            OperationLogger.info("state.prepare.isolated", profile: target, message: "Using target isolated CODEX_HOME", metadata: ["codexHome": target.codexHome])
            return CodexLaunchContext(codexHome: target.codexHome, mode: targetMode)
        case .sharedState:
            try prepareSharedHome(from: previous, target: target, initializeFromPrevious: initializeSharedFromPrevious)
            OperationLogger.info("state.prepare.sharedState", profile: target, message: "Using shared CODEX_HOME", metadata: ["codexHome": paths.sharedCodexHome.path])
            return CodexLaunchContext(codexHome: paths.sharedCodexHome.path, mode: targetMode)
        case .partialShared:
            try preparePartialSharedHome(previous: previous, target: target)
            OperationLogger.info("state.prepare.partialShared", profile: target, message: "Using target CODEX_HOME with shared config", metadata: ["codexHome": target.codexHome])
            return CodexLaunchContext(codexHome: target.codexHome, mode: targetMode)
        }
    }

    func prepareDryRun(
        previous: CodexProfile?,
        previousMode: CodexSwitchMode,
        target: CodexProfile,
        targetMode: CodexSwitchMode,
        initializeSharedFromPrevious: Bool
    ) throws -> CodexSwitchDryRunResult {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("codex-profile-manager-switch-preflight-\(UUID().uuidString)", isDirectory: true)
        let dryRunPaths = CodexStatePaths.temporary(root: root)
        try dryRunPaths.ensureDirectories()

        let dryProfilesRoot = root.appendingPathComponent("Profiles", isDirectory: true)
        try ensureSecureDirectory(dryProfilesRoot)
        let dryPrevious = try previous.map {
            try cloneProfileHome($0, into: dryProfilesRoot)
        }
        let dryTarget = try cloneProfileHome(target, into: dryProfilesRoot)
        let coordinator = CodexStateCoordinator(paths: dryRunPaths)
        let context = try coordinator.prepareForSwitch(
            previous: dryPrevious,
            previousMode: previousMode,
            target: dryTarget,
            targetMode: targetMode,
            initializeSharedFromPrevious: initializeSharedFromPrevious
        )

        return CodexSwitchDryRunResult(
            context: context,
            temporaryRoot: root,
            targetCodexHome: target.codexHome,
            preservesLocalThreads: targetMode == .sharedState,
            warnings: dryRunWarnings(for: targetMode, initializeSharedFromPrevious: initializeSharedFromPrevious)
        )
    }

    func syncAuthToSharedIfProfileIsNewer(_ profile: CodexProfile) throws {
        let profileHome = URL(fileURLWithPath: profile.codexHome)
        let profileAuth = profileHome.appendingPathComponent("auth.json")
        let sharedAuth = paths.sharedCodexHome.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: profileAuth.path) else { throw StateError.missingTargetAuth }

        let profileModifiedAt = try modificationDate(of: profileAuth)
        let sharedModifiedAt = try? modificationDate(of: sharedAuth)
        guard sharedModifiedAt == nil || profileModifiedAt > (sharedModifiedAt ?? .distantPast) else {
            return
        }

        OperationLogger.info(
            "state.shared.syncAuth",
            profile: profile,
            message: "Syncing newer profile auth into shared state"
        )
        try copyAuth(from: profileHome, to: paths.sharedCodexHome)
    }

    private func captureStateIfNeeded(from profile: CodexProfile, mode: CodexSwitchMode) throws {
        switch mode {
        case .isolated:
            return
        case .sharedState:
            OperationLogger.info("state.capture.sharedAuth", profile: profile, message: "Saving shared auth back to profile")
            try copyAuth(from: paths.sharedCodexHome, to: URL(fileURLWithPath: profile.codexHome))
        case .partialShared:
            OperationLogger.info("state.capture.partialShared", profile: profile, message: "Saving shared config from profile")
            try capturePartialSharedState(from: URL(fileURLWithPath: profile.codexHome))
        }
    }

    private func prepareSharedHome(
        from previous: CodexProfile?,
        target: CodexProfile,
        initializeFromPrevious: Bool
    ) throws {
        try ensureSecureDirectory(paths.sharedCodexHome)
        if initializeFromPrevious, let previous {
            OperationLogger.info("state.shared.initialize", profile: previous, message: "Initializing shared state from previous profile")
            try copyCodexHomeState(
                from: URL(fileURLWithPath: previous.codexHome),
                to: paths.sharedCodexHome,
                excluding: ["auth.json"]
            )
        }
        OperationLogger.info("state.shared.copyAuth", profile: target, message: "Copying target auth into shared state")
        try copyAuth(from: URL(fileURLWithPath: target.codexHome), to: paths.sharedCodexHome)
    }

    private func preparePartialSharedHome(previous: CodexProfile?, target: CodexProfile) throws {
        try ensureSecureDirectory(paths.partialSharedRoot)
        if try isDirectoryEffectivelyEmpty(paths.partialSharedRoot) {
            let seed = previous.map { URL(fileURLWithPath: $0.codexHome) } ?? URL(fileURLWithPath: target.codexHome)
            OperationLogger.info("state.partial.seed", profile: previous ?? target, message: "Seeding partial shared state")
            try capturePartialSharedState(from: seed)
        }
        try applyPartialSharedState(to: URL(fileURLWithPath: target.codexHome))
    }

    private func capturePartialSharedState(from source: URL) throws {
        try ensureSecureDirectory(paths.partialSharedRoot)
        let items = try synchronizeSharedItems(from: source, to: paths.partialSharedRoot)
        OperationLogger.info("state.partial.capture", message: "Captured partial shared items", metadata: ["items": items.joined(separator: ",")])
    }

    private func applyPartialSharedState(to target: URL) throws {
        try ensureSecureDirectory(target)
        let items = try synchronizeSharedItems(from: paths.partialSharedRoot, to: target)
        OperationLogger.info("state.partial.apply", message: "Applied partial shared items", metadata: ["items": items.joined(separator: ","), "target": target.path])
    }

    private func cloneProfileHome(_ profile: CodexProfile, into root: URL) throws -> CodexProfile {
        var cloned = profile
        let destination = root.appendingPathComponent(profile.id.uuidString, isDirectory: true)
        try ensureSecureDirectory(destination)
        try copyCodexHomeState(
            from: URL(fileURLWithPath: profile.codexHome),
            to: destination,
            excluding: []
        )
        cloned.codexHome = destination.path
        return cloned
    }

    private func dryRunWarnings(for mode: CodexSwitchMode, initializeSharedFromPrevious: Bool) -> [String] {
        switch mode {
        case .isolated:
            return ["完全独立模式不会共享旧账号的项目、线程或聊天上下文。"]
        case .sharedState:
            var warnings = ["共享状态模式会保留本地项目和线程状态，但无法保证远程线程跨账号继续复用。"]
            if !initializeSharedFromPrevious {
                warnings.append("本次未选择从当前账号初始化共享空间；如果共享空间为空，目标账号可能看不到旧上下文。")
            }
            return warnings
        case .partialShared:
            return ["部分共享模式只共享配置、工具、skills、prompts；聊天线程仍按账号独立。"]
        }
    }

    @discardableResult
    private func synchronizeSharedItems(from source: URL, to target: URL) throws -> [String] {
        try ensureSecureDirectory(target)
        let sourceItems = Set(sharedItemNames(at: source))
        let managedNames = sharedFileNames.union(sharedDirectoryNames)
        for name in managedNames.subtracting(sourceItems) {
            let staleURL = target.appendingPathComponent(name)
            if fileManager.fileExists(atPath: staleURL.path) {
                try fileManager.removeItem(at: staleURL)
            }
        }
        for item in sourceItems.sorted() {
            try replaceItem(named: item, from: source, to: target)
        }
        return sourceItems.sorted()
    }

    private func sharedItemNames(at url: URL) -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return items.compactMap { item in
            let name = item.lastPathComponent
            guard name != "." && name != ".." else { return nil }
            if sharedFileNames.contains(name) { return name }
            if sharedDirectoryNames.contains(name), (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return name
            }
            return nil
        }
    }

    private func copyCodexHomeState(from source: URL, to target: URL, excluding excludedNames: Set<String>) throws {
        try ensureSecureDirectory(target)
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
        for item in items {
            let name = item.lastPathComponent
            guard !excludedNames.contains(name) else { continue }
            try replaceItem(named: name, from: source, to: target)
        }
    }

    private func copyAuth(from source: URL, to target: URL) throws {
        let sourceAuth = source.appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: sourceAuth.path) else { throw StateError.missingTargetAuth }
        try ensureSecureDirectory(target)
        try replaceItem(named: "auth.json", from: source, to: target)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.appendingPathComponent("auth.json").path)
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.modificationDate] as? Date) ?? .distantPast
    }

    private func replaceItem(named name: String, from source: URL, to target: URL) throws {
        let sourceURL = source.appendingPathComponent(name)
        let targetURL = target.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let temporaryURL = target.appendingPathComponent(".\(name).codex-profile-manager-\(UUID().uuidString)")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try secureCopiedItem(at: temporaryURL)

        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }
        try secureCopiedItem(at: targetURL)
    }

    private func ensureSecureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func secureCopiedItem(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } else {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func isDirectoryEffectivelyEmpty(_ url: URL) throws -> Bool {
        let items = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return items.isEmpty
    }
}
