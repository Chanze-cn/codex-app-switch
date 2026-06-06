import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var isRefreshing = false
    @Published var isSwitching = false
    @Published var switchStatus: String?
    @Published var errorMessage: String?
    @Published var showingAddProfile = false
    @Published var showingHelp = false
    @Published var showingLogs = false
    @Published var pendingLoginCommand: LoginCommand?
    @Published var pendingSwitchRequest: SwitchRequest?
    @Published var selectedRenewalProfile: CodexProfile?
    @Published var selectedDeleteProfile: CodexProfile?
    @Published var statusMessage: String?
    @Published var operationLogs: [OperationLogEntry] = []

    let store = ProfileStore()
    let softwareUpdater = SoftwareUpdateController()
    private let appServer = CodexAppServerClient()
    private let launcher = CodexLauncher()
    private let stateCoordinator = CodexStateCoordinator()
    private let reminderService = RenewalReminderService()
    private var refreshTask: Task<Void, Never>?
    private var activeAccountCheckTask: Task<Void, Never>?
    private var isCheckingActiveAccount = false

    init() {
        OperationLogger.info("app.started", message: "Codex Profile Manager started")
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        activeAccountCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.verifyActiveRuntimeAccount()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        activeAccountCheckTask?.cancel()
    }

    var menuBarLabel: String {
        guard let active = store.activeProfile else { return "Codex 账号" }
        if let remaining = store.quotas[active.id]?.lowestRemainingPercent {
            return "\(active.displayName) \(remaining)%"
        }
        return active.displayName
    }

    func addProfile(name: String, colorHex: String, renewalDay: Int?) {
        OperationLogger.info("profile.add.requested", message: "User requested profile creation", metadata: ["name": name])
        do {
            let profile = try store.createProfile(name: name, colorHex: colorHex, renewalDay: renewalDay)
            try startLogin(profile)
            try AuditLogger.append(.init(kind: .loginStarted, profileID: profile.id, message: "Started official Codex login"))
            showingAddProfile = false
        } catch {
            OperationLogger.error("profile.add.failed", message: "Profile creation failed", metadata: ["name": name], error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func restorePreviousLaunch(previous: CodexProfile, mode: CodexSwitchMode) async {
        do {
            let context = try stateCoordinator.prepareForSwitch(
                previous: nil,
                previousMode: .isolated,
                target: previous,
                targetMode: mode,
                initializeSharedFromPrevious: false
            )
            var launchProfile = previous
            launchProfile.codexHome = context.codexHome
            try await launcher.launch(profile: launchProfile, workspacePath: nil)
        } catch {
            try? await launcher.launch(profile: effectiveProfile(previous, mode: mode), workspacePath: nil)
        }
    }

    func login(_ profile: CodexProfile) {
        OperationLogger.info("profile.login.requested", profile: profile, message: "User requested login")
        do {
            try store.validateProfileHome(profile)
            try startLogin(profile)
            try AuditLogger.append(.init(kind: .loginStarted, profileID: profile.id, message: "启动官方 Codex 登录"))
        } catch {
            OperationLogger.error("profile.login.failed", profile: profile, message: "Login command failed", error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func startLogin(_ profile: CodexProfile) throws {
        let command = try launcher.login(profile: profile)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        pendingLoginCommand = LoginCommand(profileName: profile.displayName, command: command)
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        let startedAt = Date()
        OperationLogger.info("quota.refreshAll.started", message: "Refreshing all profiles", metadata: ["count": "\(store.profiles.count)"])
        isRefreshing = true
        await withTaskGroup(of: (UUID, Result<QuotaSnapshot, Error>).self) { group in
            for profile in store.profiles {
                let requestProfile = profileForAccountRequest(profile)
                group.addTask {
                    do { return (profile.id, .success(try await self.appServer.fetchQuota(profile: requestProfile))) }
                    catch { return (profile.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                do {
                    switch result {
                    case .success(let snapshot):
                        try store.bindCodexAccount(email: snapshot.email, to: id)
                        try store.setQuota(snapshot, for: id)
                        try AuditLogger.append(.init(kind: .quotaRefreshed, profileID: id, message: "Refreshed quota"))
                    case .failure(let error):
                        try store.markQuotaStale(for: id, error: error)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        isRefreshing = false
        OperationLogger.info("quota.refreshAll.completed", message: "Finished refreshing all profiles", durationMs: elapsedMs(since: startedAt))
    }

    func refresh(_ profile: CodexProfile) async {
        let startedAt = Date()
        OperationLogger.info("quota.refresh.started", profile: profile, message: "Refreshing quota")
        do {
            try store.validateProfileHome(profile)
            let snapshot = try await appServer.fetchQuota(profile: profileForAccountRequest(profile))
            try store.bindCodexAccount(email: snapshot.email, to: profile.id)
            try store.setQuota(snapshot, for: profile.id)
            OperationLogger.info("quota.refresh.completed", profile: profile, message: "Quota refresh completed", durationMs: elapsedMs(since: startedAt))
        } catch {
            try? store.markQuotaStale(for: profile.id, error: error)
            OperationLogger.error("quota.refresh.failed", profile: profile, message: "Quota refresh failed", durationMs: elapsedMs(since: startedAt), error: error)
            errorMessage = error.localizedDescription
        }
    }

    func requestSwitch(to profile: CodexProfile) {
        guard !isSwitching else { return }
        statusMessage = nil
        OperationLogger.info("switch.requested", profile: profile, message: "User requested profile switch", metadata: ["defaultMode": profile.defaultSwitchMode.rawValue])
        pendingSwitchRequest = SwitchRequest(profile: profile, selectedMode: profile.defaultSwitchMode)
    }

    func setDefaultSwitchMode(_ mode: CodexSwitchMode, for profile: CodexProfile) {
        do {
            try store.updateDefaultSwitchMode(for: profile, mode: mode)
            OperationLogger.info(
                "switch.defaultMode.updated",
                profile: profile,
                message: "Updated default switch mode",
                metadata: ["mode": mode.rawValue]
            )
        } catch {
            OperationLogger.error("switch.defaultMode.failed", profile: profile, message: "Failed to update default switch mode", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func cancelSwitch() {
        OperationLogger.info("switch.cancelled", message: "User cancelled profile switch")
        pendingSwitchRequest = nil
    }

    func confirmSwitch(
        _ request: SwitchRequest,
        mode: CodexSwitchMode,
        rememberAsDefault: Bool,
        initializeSharedFromCurrent: Bool
    ) {
        pendingSwitchRequest = nil
        OperationLogger.info(
            "switch.confirmed",
            profile: request.profile,
            message: "User confirmed profile switch",
            metadata: [
                "mode": mode.rawValue,
                "rememberAsDefault": "\(rememberAsDefault)",
                "initializeSharedFromCurrent": "\(initializeSharedFromCurrent)",
            ]
        )
        if rememberAsDefault {
            do {
                try store.updateDefaultSwitchMode(for: request.profile, mode: mode)
            } catch {
                OperationLogger.error("switch.defaultMode.failed", profile: request.profile, message: "Failed to update default switch mode", error: error)
                errorMessage = error.localizedDescription
                return
            }
        }
        Task {
            await switchDirectly(
                to: request.profile,
                mode: mode,
                initializeSharedFromCurrent: initializeSharedFromCurrent
            )
        }
    }

    func preflightSwitch(
        to target: CodexProfile,
        mode targetMode: CodexSwitchMode,
        initializeSharedFromCurrent: Bool
    ) async {
        guard !isSwitching else { return }
        let startedAt = Date()
        do {
            OperationLogger.info(
                "switch.preflight.started",
                profile: target,
                message: "Switch preflight started",
                metadata: ["targetMode": targetMode.rawValue]
            )
            try store.validateProfileHome(target)
            guard target.isLoggedIn else {
                throw SwitchError.targetNotLoggedIn
            }
            let accountEmail = try await appServer.validateAuthentication(profile: profileForAccountRequest(target))
            try validateAccountIdentity(email: accountEmail, for: target.id)
            let previous = store.activeProfile
            let previousMode = store.activeRuntimeMode
            if let previous {
                try await assertNoActiveTasks(previous: previous, previousMode: previousMode)
            }
            let result = try stateCoordinator.prepareDryRun(
                previous: previous,
                previousMode: previousMode,
                target: target,
                targetMode: targetMode,
                initializeSharedFromPrevious: initializeSharedFromCurrent
            )
            try? FileManager.default.removeItem(at: result.temporaryRoot)

            let preservation = result.preservesLocalThreads ? "会尽量保留本地项目和线程状态" : "不会共享聊天线程上下文"
            let warningText = result.warnings.isEmpty ? "" : "；\(result.warnings.joined(separator: "；"))"
            statusMessage = "模拟预检通过：将以 \(targetMode.title) 启动，目标 CODEX_HOME 为 \(result.targetCodexHome)，\(preservation)\(warningText)"
            OperationLogger.info(
                "switch.preflight.completed",
                profile: target,
                message: "Switch preflight completed",
                metadata: ["targetMode": targetMode.rawValue, "launchCodexHome": result.context.codexHome],
                durationMs: elapsedMs(since: startedAt)
            )
        } catch {
            OperationLogger.error(
                "switch.preflight.failed",
                profile: target,
                message: "Switch preflight failed",
                metadata: ["targetMode": targetMode.rawValue],
                durationMs: elapsedMs(since: startedAt),
                error: error
            )
            errorMessage = error.localizedDescription
        }
    }

    func switchDirectly(
        to target: CodexProfile,
        mode targetMode: CodexSwitchMode,
        initializeSharedFromCurrent: Bool
    ) async {
        guard !isSwitching else { return }
        isSwitching = true
        switchStatus = "正在验证目标账号..."
        defer {
            isSwitching = false
            switchStatus = nil
        }
        let startedAt = Date()
        let previous = store.activeProfile
        let previousMode = store.activeRuntimeMode
        var didStopDesktop = false
        do {
            OperationLogger.info(
                "switch.started",
                profile: target,
                message: "Switch flow started",
                metadata: [
                    "targetMode": targetMode.rawValue,
                    "previousProfile": previous?.name ?? "",
                    "previousMode": previousMode.rawValue,
                ]
            )
            try store.validateProfileHome(target)
            guard target.isLoggedIn else {
                throw SwitchError.targetNotLoggedIn
            }
            let accountEmail = try await appServer.validateAuthentication(profile: profileForAccountRequest(target))
            try store.bindCodexAccount(email: accountEmail, to: target.id)
            if let previous {
                switchStatus = "正在检查当前账号任务..."
                try await assertNoActiveTasks(previous: previous, previousMode: previousMode)
            }

            try AuditLogger.append(.init(kind: .switchStarted, profileID: target.id, message: "Switch started"))
            switchStatus = "正在停止 Codex..."
            OperationLogger.info("switch.desktop.stop.started", message: "Stopping Codex Desktop")
            await launcher.stopDesktop()
            OperationLogger.info("switch.desktop.stop.completed", message: "Stopped Codex Desktop")
            didStopDesktop = true

            let prepareStartedAt = Date()
            switchStatus = "正在准备 \(targetMode.title) 状态..."
            let context = try stateCoordinator.prepareForSwitch(
                previous: previous,
                previousMode: previousMode,
                target: target,
                targetMode: targetMode,
                initializeSharedFromPrevious: initializeSharedFromCurrent
            )
            OperationLogger.info(
                "switch.statePrepared",
                profile: target,
                message: "Prepared Codex state for switch",
                metadata: ["launchMode": context.mode.rawValue, "codexHome": context.codexHome],
                durationMs: elapsedMs(since: prepareStartedAt)
            )
            var launchProfile = target
            launchProfile.codexHome = context.codexHome
            let launchStartedAt = Date()
            switchStatus = "正在启动 Codex..."
            try await launcher.launch(profile: launchProfile, workspacePath: nil)
            OperationLogger.info("switch.desktop.launch.completed", profile: target, message: "Launched Codex Desktop", metadata: ["codexHome": context.codexHome], durationMs: elapsedMs(since: launchStartedAt))
            try store.markActive(target.id, runtimeMode: context.mode)
            try AuditLogger.append(.init(kind: .switchCompleted, profileID: target.id, message: "Switch completed"))
            OperationLogger.info("switch.completed", profile: target, message: "Switch flow completed", metadata: ["mode": context.mode.rawValue], durationMs: elapsedMs(since: startedAt))
        } catch {
            try? AuditLogger.append(.init(kind: .switchFailed, profileID: target.id, message: error.localizedDescription))
            OperationLogger.error("switch.failed", profile: target, message: "Switch flow failed", metadata: ["mode": targetMode.rawValue], durationMs: elapsedMs(since: startedAt), error: error)
            if didStopDesktop, let previous {
                await restorePreviousLaunch(previous: previous, mode: previousMode)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func effectiveProfile(_ profile: CodexProfile, mode: CodexSwitchMode) -> CodexProfile {
        var effective = profile
        if mode == .sharedState {
            effective.codexHome = AppPaths.sharedCodexHome.path
        }
        return effective
    }

    private func assertNoActiveTasks(previous: CodexProfile, previousMode: CodexSwitchMode) async throws {
        do {
            let checkStartedAt = Date()
            let threads = try await appServer.recentThreads(profile: effectiveProfile(previous, mode: previousMode))
            OperationLogger.info(
                "switch.activeTasks.checked",
                profile: previous,
                message: "Checked current profile active tasks",
                metadata: ["threadCount": "\(threads.count)"],
                durationMs: elapsedMs(since: checkStartedAt)
            )
            let hasActive = threads.contains { thread in
                guard let status = thread.status?.lowercased() else { return false }
                return status.contains("active") || status.contains("running")
            }
            if hasActive { throw CodexLauncher.LauncherError.activeTasks }
        } catch CodexLauncher.LauncherError.activeTasks {
            OperationLogger.warning("switch.blocked.activeTasks", profile: previous, message: "Switch blocked because active tasks were detected")
            throw CodexLauncher.LauncherError.activeTasks
        } catch {
            OperationLogger.warning("switch.activeTasks.checkFailed", profile: previous, message: "Could not confirm active tasks", error: error)
            throw SwitchError.activeTaskCheckFailed(error.localizedDescription)
        }
    }

    private func validateAccountIdentity(email: String?, for id: UUID) throws {
        guard let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return }
        if let existing = store.profiles.first(where: {
            $0.id != id && $0.accountEmail?.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            throw ProfileError.accountAlreadyBound(email: normalized, profileName: existing.displayName)
        }
        if let target = store.profiles.first(where: { $0.id == id }),
           let bound = target.accountEmail,
           bound.caseInsensitiveCompare(normalized) != .orderedSame {
            throw ProfileError.accountMismatch(expected: bound, actual: normalized)
        }
    }

    private func profileForAccountRequest(_ profile: CodexProfile) -> CodexProfile {
        guard store.activeProfileID == profile.id else { return profile }
        return effectiveProfile(profile, mode: store.activeRuntimeMode)
    }

    private func verifyActiveRuntimeAccount() async {
        guard !isCheckingActiveAccount, !isSwitching else { return }
        guard let active = store.activeProfile else { return }
        guard launcher.isDesktopRunning() else { return }
        isCheckingActiveAccount = true
        defer { isCheckingActiveAccount = false }

        let runtimeMode = store.activeRuntimeMode
        let requestProfile = effectiveProfile(active, mode: runtimeMode)
        do {
            let email = try await appServer.validateAuthentication(profile: requestProfile)
            try reconcileActiveRuntime(email: email, previous: active, runtimeMode: runtimeMode)
        } catch {
            OperationLogger.warning(
                "activeAccount.check.failed",
                profile: active,
                message: "Could not verify active runtime account",
                metadata: ["mode": runtimeMode.rawValue],
                error: error
            )
        }
    }

    private func reconcileActiveRuntime(email: String?, previous: CodexProfile, runtimeMode: CodexSwitchMode) throws {
        guard let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return }
        if previous.accountEmail?.caseInsensitiveCompare(normalized) == .orderedSame {
            return
        }
        if previous.accountEmail == nil {
            try store.bindCodexAccount(email: normalized, to: previous.id)
            statusMessage = "已确认当前启动账号：\(normalized)。"
            OperationLogger.info(
                "activeAccount.bound",
                profile: previous,
                message: "Bound active profile from runtime account check",
                metadata: ["accountEmail": normalized, "mode": runtimeMode.rawValue]
            )
            return
        }
        if let matching = store.profiles.first(where: {
            $0.accountEmail?.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            try store.markActive(matching.id, runtimeMode: runtimeMode)
            statusMessage = "已校正当前启动账号：检测到 Codex 正在使用 \(matching.displayName)。"
            OperationLogger.warning(
                "activeAccount.corrected",
                profile: matching,
                message: "Corrected active profile marker from runtime account",
                metadata: ["previousProfile": previous.displayName, "accountEmail": normalized, "mode": runtimeMode.rawValue]
            )
        } else {
            store.clearActiveProfile()
            statusMessage = "当前 Codex Desktop 登录的是未绑定账号 \(normalized)，已清除当前启动标记。"
            OperationLogger.warning(
                "activeAccount.unbound",
                profile: previous,
                message: "Cleared active marker because runtime account is not bound",
                metadata: ["accountEmail": normalized, "mode": runtimeMode.rawValue]
            )
        }
    }

    func updateRenewal(profile: CodexProfile, day: Int?, reminderDays: [Int]) async {
        OperationLogger.info(
            "renewal.update.requested",
            profile: profile,
            message: "User updated renewal settings",
            metadata: ["day": day.map(String.init) ?? "disabled", "reminders": reminderDays.map(String.init).joined(separator: ",")]
        )
        var updated = profile
        updated.renewalDay = day
        updated.reminderDays = reminderDays
        do {
            try store.update(updated)
            _ = try? await reminderService.requestAuthorization()
            try await reminderService.schedule(for: updated)
            OperationLogger.info("renewal.update.completed", profile: updated, message: "Renewal settings updated")
        } catch {
            OperationLogger.error("renewal.update.failed", profile: profile, message: "Failed to update renewal settings", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func requestRenewalEdit(_ profile: CodexProfile) {
        OperationLogger.info("renewal.edit.requested", profile: profile, message: "User requested renewal edit")
        selectedRenewalProfile = profile
    }

    func requestDelete(_ profile: CodexProfile) {
        OperationLogger.info("profile.delete.requested", profile: profile, message: "User requested profile deletion")
        selectedDeleteProfile = profile
    }

    func deleteSelectedProfile() {
        guard let profile = selectedDeleteProfile else { return }
        do {
            try store.deleteProfile(profile)
            OperationLogger.info("profile.delete.completed", profile: profile, message: "Profile deleted")
            selectedDeleteProfile = nil
        } catch {
            OperationLogger.error("profile.delete.failed", profile: profile, message: "Profile deletion failed", error: error)
            errorMessage = error.localizedDescription
        }
    }

    func showLogs() {
        refreshLogs()
        showingLogs = true
        OperationLogger.info("logs.opened", message: "User opened operation logs")
    }

    func refreshLogs() {
        operationLogs = OperationLogger.recent()
    }

    func openLogDirectory() {
        OperationLogger.info("logs.directory.opened", message: "User opened log directory")
        NSWorkspace.shared.open(AppPaths.root)
    }

    func openUsagePage() {
        openExternalPage("https://chatgpt.com/codex/settings/usage", event: "usagePage.opened")
    }

    func openBillingPage() {
        openExternalPage("https://chatgpt.com/#settings/Subscription", event: "billingPage.opened")
    }

    func quit() {
        OperationLogger.info("app.quit.requested", message: "User requested app quit")
        NSApplication.shared.terminate(nil)
    }

    private func elapsedMs(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1000))
    }

    private func openExternalPage(_ value: String, event: String) {
        guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
            let error = ExternalPageError.openFailed
            OperationLogger.error(event, message: "Failed to open external page", metadata: ["url": value], error: error)
            errorMessage = error.localizedDescription
            return
        }
        OperationLogger.info(event, message: "Opened external page", metadata: ["url": value])
    }
}

struct LoginCommand: Identifiable {
    let id = UUID()
    let profileName: String
    let command: String
}

struct SwitchRequest: Identifiable {
    let id = UUID()
    let profile: CodexProfile
    let selectedMode: CodexSwitchMode
}

enum SwitchError: LocalizedError {
    case targetNotLoggedIn
    case activeTaskCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .targetNotLoggedIn:
            "目标账号还没有完成登录。请先点击“登录/重新登录”，完成后再切换。"
        case .activeTaskCheckFailed(let message):
            "无法确认当前账号没有运行中的 Codex 任务：\(message)。为避免丢失上下文，已阻止切换。"
        }
    }
}

enum ExternalPageError: LocalizedError {
    case openFailed

    var errorDescription: String? {
        "无法打开网页，请检查默认浏览器设置后重试。"
    }
}
