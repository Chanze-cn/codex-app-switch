import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [CodexProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var quotas: [UUID: QuotaSnapshot] = [:]
    @Published private(set) var handoffs: [HandoffPackage] = []

    private let defaults = UserDefaults.standard
    private let activeProfileKey = "activeProfileID"
    private let activeRuntimeModeKey = "activeRuntimeMode"

    init() {
        do {
            try AppPaths.ensureDirectories()
        } catch {
            OperationLogger.error("store.directories.failed", message: "Failed to prepare app directories", error: error)
        }
        do {
            profiles = try AtomicJSONStore.load([CodexProfile].self, from: AppPaths.profilesFile, default: [])
        } catch {
            OperationLogger.error("store.profiles.load.failed", message: "Failed to load profiles", error: error)
        }
        do {
            quotas = try AtomicJSONStore.load([UUID: QuotaSnapshot].self, from: AppPaths.quotaFile, default: [:])
        } catch {
            OperationLogger.error("store.quotas.load.failed", message: "Failed to load quota cache", error: error)
        }
        activeProfileID = defaults.string(forKey: activeProfileKey).flatMap(UUID.init(uuidString:))
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = nil
            defaults.removeObject(forKey: activeProfileKey)
            defaults.set(CodexSwitchMode.isolated.rawValue, forKey: activeRuntimeModeKey)
        }
        do {
            handoffs = try loadHandoffs()
        } catch {
            OperationLogger.error("store.handoffs.load.failed", message: "Failed to load handoffs", error: error)
        }
    }

    func createProfile(name: String, colorHex: String, renewalDay: Int?) throws -> CodexProfile {
        let id = UUID()
        let home = AppPaths.defaultCodexHome(profileID: id)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = CodexProfile(
            id: id,
            name: trimmedName.isEmpty ? "待绑定账号" : trimmedName,
            colorHex: colorHex,
            codexHome: home.path,
            renewalDay: renewalDay.flatMap { (1...31).contains($0) ? $0 : nil }
        )
        profiles.append(profile)
        try persistProfiles()
        try AuditLogger.append(.init(kind: .profileCreated, profileID: id, message: "Created profile \(profile.displayName)"))
        return profile
    }

    func update(_ profile: CodexProfile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var validated = profile
        validated.renewalDay = profile.renewalDay.flatMap { (1...31).contains($0) ? $0 : nil }
        validated.reminderDays = profile.reminderDays.filter { [7, 3, 1].contains($0) }.sorted(by: >)
        profiles[index] = validated
        try persistProfiles()
    }

    func deleteProfile(_ profile: CodexProfile) throws {
        let homeURL = try managedProfileHomeURL(profile)
        profiles.removeAll { $0.id == profile.id }
        quotas.removeValue(forKey: profile.id)
        if activeProfileID == profile.id {
            activeProfileID = nil
            defaults.removeObject(forKey: activeProfileKey)
            defaults.set(CodexSwitchMode.isolated.rawValue, forKey: activeRuntimeModeKey)
        }
        try persistProfiles()
        try AtomicJSONStore.save(quotas, to: AppPaths.quotaFile)
        if FileManager.default.fileExists(atPath: homeURL.path) {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: homeURL, resultingItemURL: &trashedURL)
        }
        try AuditLogger.append(.init(kind: .profileDeleted, profileID: profile.id, message: "Deleted profile \(profile.displayName)"))
    }

    func markActive(_ id: UUID, runtimeMode: CodexSwitchMode? = nil) throws {
        activeProfileID = id
        defaults.set(id.uuidString, forKey: activeProfileKey)
        if let runtimeMode {
            defaults.set(runtimeMode.rawValue, forKey: activeRuntimeModeKey)
        }
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].lastUsedAt = Date()
            try persistProfiles()
        }
    }

    func updateDefaultSwitchMode(for profile: CodexProfile, mode: CodexSwitchMode) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].defaultSwitchMode = mode
        try persistProfiles()
    }

    func bindCodexAccount(email: String?, to id: UUID) throws {
        guard let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return }
        if let existing = profiles.first(where: {
            $0.id != id && $0.accountEmail?.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            throw ProfileError.accountAlreadyBound(email: normalized, profileName: existing.displayName)
        }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let bound = profiles[index].accountEmail,
           bound.caseInsensitiveCompare(normalized) != .orderedSame {
            throw ProfileError.accountMismatch(expected: bound, actual: normalized)
        }
        guard profiles[index].accountEmail != normalized else { return }
        profiles[index].accountEmail = normalized
        try persistProfiles()
        OperationLogger.info(
            "profile.account.bound",
            profile: profiles[index],
            message: "Bound profile to Codex account",
            metadata: ["accountEmail": normalized]
        )
    }

    func setQuota(_ snapshot: QuotaSnapshot, for id: UUID) throws {
        quotas[id] = snapshot
        try AtomicJSONStore.save(quotas, to: AppPaths.quotaFile)
    }

    func markQuotaStale(for id: UUID, error: Error) throws {
        if var existing = quotas[id] {
            existing.stale = true
            existing.errorMessage = error.localizedDescription
            quotas[id] = existing
        } else {
            quotas[id] = QuotaSnapshot(
                fetchedAt: Date(),
                stale: true,
                errorMessage: error.localizedDescription
            )
        }
        try AtomicJSONStore.save(quotas, to: AppPaths.quotaFile)
        OperationLogger.warning(
            "quota.refresh.failed",
            message: "Quota refresh failed; showing cached data",
            metadata: ["profileID": id.uuidString],
            error: error
        )
    }

    func addHandoff(_ handoff: HandoffPackage) throws {
        handoffs.insert(handoff, at: 0)
        try AtomicJSONStore.save(handoff, to: AppPaths.handoffsRoot.appendingPathComponent("\(handoff.id).json"))
    }

    func validateProfileHome(_ profile: CodexProfile) throws {
        let url = try managedProfileHomeURL(profile)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o077 == 0 else {
            throw ProfileError.insecurePermissions
        }
    }

    var activeProfile: CodexProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var activeRuntimeMode: CodexSwitchMode {
        defaults.string(forKey: activeRuntimeModeKey).flatMap(CodexSwitchMode.init(rawValue:)) ?? .isolated
    }

    var sortedProfiles: [CodexProfile] {
        Self.sortedProfiles(profiles, activeProfileID: activeProfileID, quotas: quotas)
    }

    nonisolated static func sortedProfiles(
        _ profiles: [CodexProfile],
        activeProfileID: UUID?,
        quotas: [UUID: QuotaSnapshot]
    ) -> [CodexProfile] {
        profiles.sorted {
            if $0.id == activeProfileID { return true }
            if $1.id == activeProfileID { return false }
            let left = quotas[$0.id]?.lowestRemainingPercent ?? -1
            let right = quotas[$1.id]?.lowestRemainingPercent ?? -1
            if left != right { return left > right }
            return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
        }
    }

    private func persistProfiles() throws {
        try AtomicJSONStore.save(profiles, to: AppPaths.profilesFile)
    }

    private func managedProfileHomeURL(_ profile: CodexProfile) throws -> URL {
        let url = URL(fileURLWithPath: profile.codexHome).standardizedFileURL.resolvingSymlinksInPath()
        let profilesRoot = AppPaths.profilesRoot.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard url.path.hasPrefix(profilesRoot), url.lastPathComponent == profile.id.uuidString else {
            throw ProfileError.homeOutsideManagedDirectory
        }
        return url
    }

    private func loadHandoffs() throws -> [HandoffPackage] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: AppPaths.handoffsRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        return urls.compactMap {
            try? AtomicJSONStore.decoder.decode(HandoffPackage.self, from: Data(contentsOf: $0))
        }.sorted { $0.createdAt > $1.createdAt }
    }
}

enum ProfileError: LocalizedError {
    case homeOutsideManagedDirectory
    case insecurePermissions
    case accountAlreadyBound(email: String, profileName: String)
    case accountMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .homeOutsideManagedDirectory: "账号目录不在应用管理的安全目录中。"
        case .insecurePermissions: "账号目录权限不安全，不能允许其他用户访问。"
        case .accountAlreadyBound(let email, let profileName):
            "Codex 账号 \(email) 已绑定到“\(profileName)”。一个 Codex 账号只能对应一个账号配置。"
        case .accountMismatch(let expected, let actual):
            "这个配置已绑定 \(expected)，但当前登录的是 \(actual)。为避免混淆，请重新登录原账号，或删除该配置后为新账号重新创建。"
        }
    }
}

enum AuditLogger {
    static func append(_ entry: AuditEntry) throws {
        try AppPaths.ensureDirectories()
        let data = try AtomicJSONStore.encoder.encode(entry) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: AppPaths.auditFile.path) {
            let handle = try FileHandle(forWritingTo: AppPaths.auditFile)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: AppPaths.auditFile, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.auditFile.path)
        OperationLogger.info(
            "audit.\(entry.kind.rawValue)",
            message: entry.message,
            metadata: entry.profileID.map { ["profileID": $0.uuidString] } ?? [:]
        )
    }
}
