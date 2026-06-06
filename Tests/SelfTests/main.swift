import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let snapshot = QuotaSnapshot(
    primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: nil),
    secondary: RateLimitWindow(usedPercent: 70, windowDurationMins: 10_080, resetsAt: nil),
    fetchedAt: Date(),
    stale: false
)
expect(snapshot.lowestRemainingPercent == 30, "lowest quota window should drive status")
expect(RateLimitWindow(usedPercent: -20, windowDurationMins: nil, resetsAt: nil).remainingPercent == 100, "remaining quota should not exceed 100 percent")
expect(RateLimitWindow(usedPercent: 120, windowDurationMins: nil, resetsAt: nil).remainingPercent == 0, "remaining quota should not fall below zero")

let unboundProfile = CodexProfile(name: "工作账号", codexHome: "/tmp/unbound")
expect(unboundProfile.displayName == "工作账号", "unbound profile should use its note as display name")
expect(unboundProfile.alias == nil, "unbound profile should not expose a duplicate alias")

let boundProfile = CodexProfile(name: "工作账号", accountEmail: "user@example.com", codexHome: "/tmp/bound")
expect(boundProfile.displayName == "user@example.com", "bound profile should use the real Codex account")
expect(boundProfile.alias == "工作账号", "bound profile should retain its note as an alias")

let decodedLegacyProfile = try AtomicJSONStore.decoder.decode(
    CodexProfile.self,
    from: Data("""
    {
      "id": "\(UUID().uuidString)",
      "name": "旧账号",
      "colorHex": "#4F7CAC",
      "codexHome": "/tmp/legacy",
      "renewalDay": null,
      "reminderDays": [7, 3, 1],
      "createdAt": "2026-06-04T00:00:00Z"
    }
    """.utf8)
)
expect(decodedLegacyProfile.accountEmail == nil, "legacy profiles should decode without account identity")

let handoff = HandoffPackage(
    id: UUID(),
    sourceProfileID: UUID(),
    targetProfileID: UUID(),
    workspacePath: "/tmp/project",
    gitBranch: "feature/profile",
    threadID: "thread-123",
    summary: "Implement switching",
    notes: "Keep auth isolated",
    unfinishedItems: ["Add tests"],
    createdAt: Date()
)
expect(handoff.prompt.contains("/tmp/project"), "handoff should contain workspace")
expect(handoff.prompt.contains("feature/profile"), "handoff should contain branch")
expect(handoff.prompt.contains("Add tests"), "handoff should contain unfinished work")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
let clamped = RenewalReminderService().nextRenewalDate(day: 31, after: february, calendar: calendar)!
expect(calendar.component(.day, from: clamped) == 28, "renewal should clamp to final day of short month")

let afterRenewal = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
let nextMonth = RenewalReminderService().nextRenewalDate(day: 12, after: afterRenewal, calendar: calendar)!
expect(calendar.component(.month, from: nextMonth) == 7, "past renewal day should move to next month")

let runtimePath = CodexRuntimeEnvironment.runtimePath(codexExecutable: "/opt/homebrew/bin/codex")
expect(runtimePath.split(separator: ":").contains("/opt/homebrew/bin"), "runtime PATH should include Homebrew for env node")

let fileManager = FileManager.default
let testRoot = fileManager.temporaryDirectory.appendingPathComponent("codex-profile-manager-tests-\(UUID().uuidString)", isDirectory: true)
defer { try? fileManager.removeItem(at: testRoot) }

let quotaCacheURL = testRoot.appendingPathComponent("quota-cache.json")
try AtomicJSONStore.save([UUID(): snapshot], to: quotaCacheURL)
expect(fileManager.fileExists(atPath: quotaCacheURL.path), "atomic JSON save should create quota cache file")
let quotaAttributes = try fileManager.attributesOfItem(atPath: quotaCacheURL.path)
let quotaPermissions = (quotaAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
expect(quotaPermissions & 0o777 == 0o600, "atomic JSON save should restrict cache file permissions")

let lowQuotaProfile = CodexProfile(id: UUID(), name: "current", codexHome: "/tmp/current")
let highQuotaProfile = CodexProfile(id: UUID(), name: "backup", codexHome: "/tmp/backup")
let sortedProfiles = ProfileStore.sortedProfiles(
    [highQuotaProfile, lowQuotaProfile],
    activeProfileID: lowQuotaProfile.id,
    quotas: [
        lowQuotaProfile.id: QuotaSnapshot(
            primary: RateLimitWindow(usedPercent: 95, windowDurationMins: nil, resetsAt: nil),
            fetchedAt: Date(),
            stale: false
        ),
        highQuotaProfile.id: QuotaSnapshot(
            primary: RateLimitWindow(usedPercent: 5, windowDurationMins: nil, resetsAt: nil),
            fetchedAt: Date(),
            stale: false
        ),
    ]
)
expect(sortedProfiles.first?.id == lowQuotaProfile.id, "active profile should stay pinned above higher-quota profiles")

func writeFile(_ path: URL, _ content: String) throws {
    try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try Data(content.utf8).write(to: path)
}

func readFile(_ path: URL) -> String {
    (try? String(contentsOf: path, encoding: .utf8)) ?? ""
}

let previousHome = testRoot.appendingPathComponent("previous-home", isDirectory: true)
let targetHome = testRoot.appendingPathComponent("target-home", isDirectory: true)
try fileManager.createDirectory(at: previousHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try fileManager.createDirectory(at: targetHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try writeFile(previousHome.appendingPathComponent("auth.json"), "previous-auth")
try writeFile(previousHome.appendingPathComponent("state.sqlite"), "previous-thread-state")
try writeFile(previousHome.appendingPathComponent("config.toml"), "previous-config")
try writeFile(previousHome.appendingPathComponent("skills/example/SKILL.md"), "previous-skill")
try writeFile(targetHome.appendingPathComponent("auth.json"), "target-auth")
try writeFile(targetHome.appendingPathComponent("config.toml"), "target-config")

let previousProfile = CodexProfile(id: UUID(), name: "previous", codexHome: previousHome.path)
let targetProfile = CodexProfile(id: UUID(), name: "target", codexHome: targetHome.path)

let isolatedPaths = CodexStatePaths.temporary(root: testRoot.appendingPathComponent("isolated-state", isDirectory: true))
let isolatedContext = try CodexStateCoordinator(paths: isolatedPaths).prepareForSwitch(
    previous: previousProfile,
    previousMode: .isolated,
    target: targetProfile,
    targetMode: .isolated,
    initializeSharedFromPrevious: false
)
expect(isolatedContext.codexHome == targetHome.path, "isolated mode should launch the target profile CODEX_HOME")
expect(!fileManager.fileExists(atPath: isolatedPaths.sharedCodexHome.appendingPathComponent("state.sqlite").path), "isolated mode should not copy state into shared home")

let sharedPaths = CodexStatePaths.temporary(root: testRoot.appendingPathComponent("shared-state", isDirectory: true))
let sharedContext = try CodexStateCoordinator(paths: sharedPaths).prepareForSwitch(
    previous: previousProfile,
    previousMode: .isolated,
    target: targetProfile,
    targetMode: .sharedState,
    initializeSharedFromPrevious: true
)
expect(sharedContext.codexHome == sharedPaths.sharedCodexHome.path, "shared state mode should launch the shared CODEX_HOME")
expect(readFile(sharedPaths.sharedCodexHome.appendingPathComponent("auth.json")) == "target-auth", "shared state should use target auth")
expect(readFile(sharedPaths.sharedCodexHome.appendingPathComponent("state.sqlite")) == "previous-thread-state", "shared state should preserve previous local thread state")
expect(readFile(sharedPaths.sharedCodexHome.appendingPathComponent("config.toml")) == "previous-config", "shared state should preserve previous config when initialized")

let partialPaths = CodexStatePaths.temporary(root: testRoot.appendingPathComponent("partial-state", isDirectory: true))
_ = try CodexStateCoordinator(paths: partialPaths).prepareForSwitch(
    previous: previousProfile,
    previousMode: .isolated,
    target: targetProfile,
    targetMode: .partialShared,
    initializeSharedFromPrevious: false
)
expect(readFile(targetHome.appendingPathComponent("auth.json")) == "target-auth", "partial shared mode should keep target auth")
expect(readFile(targetHome.appendingPathComponent("config.toml")) == "previous-config", "partial shared mode should apply shared config")
expect(readFile(targetHome.appendingPathComponent("state.sqlite")) != "previous-thread-state", "partial shared mode should not copy chat/thread state")

let dryRunResult = try CodexStateCoordinator().prepareDryRun(
    previous: previousProfile,
    previousMode: .isolated,
    target: targetProfile,
    targetMode: .sharedState,
    initializeSharedFromPrevious: true
)
defer { try? fileManager.removeItem(at: dryRunResult.temporaryRoot) }
expect(dryRunResult.preservesLocalThreads, "shared state dry-run should report local thread preservation")
expect(fileManager.fileExists(atPath: dryRunResult.temporaryRoot.path), "dry-run should prepare a temporary root for verification")

print("All Codex Profile Manager self-tests passed.")
