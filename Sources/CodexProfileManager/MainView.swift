import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var store: ProfileStore

    init(model: AppModel) {
        self.model = model
        store = model.store
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isSwitching {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.switchStatus ?? "正在切换账号...")
                        .font(.caption)
                    Spacer()
                }
                .padding(10)
                .background(.blue.opacity(0.10))
                Divider()
            }
            if let request = model.pendingSwitchRequest {
                SwitchConfirmationView(
                    request: request,
                    activeProfile: store.activeProfile,
                    confirm: { mode, rememberAsDefault, initializeSharedFromCurrent in
                        model.confirmSwitch(
                            request,
                            mode: mode,
                            rememberAsDefault: rememberAsDefault,
                            initializeSharedFromCurrent: initializeSharedFromCurrent
                        )
                    },
                    preflight: { mode, initializeSharedFromCurrent in
                        Task {
                            await model.preflightSwitch(
                                to: request.profile,
                                mode: mode,
                                initializeSharedFromCurrent: initializeSharedFromCurrent
                            )
                        }
                    },
                    cancel: { model.cancelSwitch() }
                )
                Divider()
            }
            if store.profiles.isEmpty {
                ContentUnavailableView(
                    "还没有 Codex 账号",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("点击右上角 +，创建第一个账号配置并完成官方登录。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let statusMessage = model.statusMessage {
                            StatusBanner(message: statusMessage) {
                                model.statusMessage = nil
                            }
                        }
                        ForEach(store.sortedProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                quota: store.quotas[profile.id],
                                isActive: store.activeProfileID == profile.id,
                                isBusy: model.isSwitching,
                                activeRuntimeMode: store.activeProfileID == profile.id ? store.activeRuntimeMode : nil,
                                refresh: { Task { await model.refresh(profile) } },
                                login: { model.login(profile) },
                                switchProfile: { model.requestSwitch(to: profile) },
                                changeMode: { model.setDefaultSwitchMode($0, for: profile) },
                                editRenewal: { model.requestRenewalEdit(profile) },
                                deleteProfile: { model.requestDelete(profile) }
                            )
                        }
                    }
                    .padding()
                }
            }
            Divider()
            footer
        }
        .sheet(isPresented: $model.showingAddProfile) {
            AddProfileView { name, color, day in model.addProfile(name: name, colorHex: color, renewalDay: day) }
        }
        .sheet(isPresented: $model.showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $model.showingLogs) {
            OperationLogView(
                entries: model.operationLogs,
                refresh: { model.refreshLogs() },
                openDirectory: { model.openLogDirectory() }
            )
        }
        .sheet(item: $model.pendingLoginCommand) { login in
            LoginCommandView(login: login) {
                model.pendingLoginCommand = nil
                Task { await model.refreshAll() }
            }
        }
        .sheet(item: $model.selectedRenewalProfile) { profile in
            RenewalEditorView(profile: profile) { day, reminders in
                Task { await model.updateRenewal(profile: profile, day: day, reminderDays: reminders) }
                model.selectedRenewalProfile = nil
            }
        }
        .alert("删除账号配置？", isPresented: Binding(
            get: { model.selectedDeleteProfile != nil },
            set: { if !$0 { model.selectedDeleteProfile = nil } }
        )) {
            Button("取消", role: .cancel) { model.selectedDeleteProfile = nil }
            Button("删除并移到废纸篓", role: .destructive) { model.deleteSelectedProfile() }
        } message: {
            Text("会删除这个账号在本工具中的配置，并把独立 CODEX_HOME 目录移到废纸篓。不会注销你的 OpenAI 账号。")
        }
        .alert("Codex 多账号管理器", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("确定") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.refreshAll() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 账号")
                    .font(.headline)
                if let active = store.activeProfile {
                    HStack(spacing: 6) {
                        Text(active.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ModeBadge(mode: store.activeRuntimeMode, prefix: "当前启动")
                    }
                } else {
                    Text("尚未通过本软件启动 Codex 账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
            Button { model.quit() } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("退出软件")
            Button { Task { await model.refreshAll() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing || model.isSwitching)
            .help("刷新全部账号额度")
            Button { model.showingAddProfile = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(model.isSwitching)
            .help("添加账号")
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button { model.showingHelp = true } label: {
                Label("说明", systemImage: "questionmark.circle")
            }
            Button { model.showLogs() } label: {
                Label("日志", systemImage: "list.bullet.rectangle")
            }
            Spacer()
            Menu {
                Button("官方额度页") { model.openUsagePage() }
                Button("订阅管理") { model.openBillingPage() }
                Divider()
                Button("退出软件") { model.quit() }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
        .font(.caption)
        .padding()
    }
}

private struct StatusBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileCard: View {
    let profile: CodexProfile
    let quota: QuotaSnapshot?
    let isActive: Bool
    let isBusy: Bool
    let activeRuntimeMode: CodexSwitchMode?
    let refresh: () -> Void
    let login: () -> Void
    let switchProfile: () -> Void
    let changeMode: (CodexSwitchMode) -> Void
    let editRenewal: () -> Void
    let deleteProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(Color(hex: profile.colorHex)).frame(width: 10, height: 10)
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if isActive {
                    Text("正在使用")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                Text(loginState.title)
                    .font(.caption2.bold())
                    .foregroundStyle(loginState.color)
                Spacer()
                Text(quota?.planType?.uppercased() ?? "未登录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let alias = profile.alias {
                Label("备注：\(alias)", systemImage: "tag")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if profile.accountEmail == nil {
                Label("登录后将自动绑定 Codex 账号", systemImage: "link.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Image(systemName: profile.defaultSwitchMode.icon)
                    .font(.title3)
                    .foregroundStyle(profile.defaultSwitchMode.tint)
                    .frame(width: 32, height: 32)
                    .background(profile.defaultSwitchMode.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("默认模式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(profile.defaultSwitchMode.title)
                            .font(.caption.bold())
                            .foregroundStyle(profile.defaultSwitchMode.tint)
                        if let activeRuntimeMode, activeRuntimeMode != profile.defaultSwitchMode {
                            ModeBadge(mode: activeRuntimeMode, prefix: "本次")
                        }
                    }
                    Text(profile.defaultSwitchMode.shortSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Menu {
                    ForEach(CodexSwitchMode.allCases) { mode in
                        Button {
                            changeMode(mode)
                        } label: {
                            Label(mode.title, systemImage: mode.icon)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .help("修改默认切换模式")
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            if let quota {
                QuotaRow(label: "5 小时", window: quota.primary)
                QuotaRow(label: "每周", window: quota.secondary)
                HStack {
                    Text("额外额度")
                    Spacer()
                    Text(quota.credits?.unlimited == true ? "无限" : quota.credits?.balance ?? "无")
                }
                .font(.caption)
                freshness(quota)
            } else {
                Text(profile.isLoggedIn ? "检测到登录凭据，但尚未验证真实账号。请点击“刷新额度”。" : "尚未完成登录。请点击“登录”，完成后再刷新额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            RenewalSummary(profile: profile)
            HStack {
                Button(action: editRenewal) {
                    Image(systemName: "calendar.badge.clock")
                }
                .help("续费设置")
                Spacer()
                Button(profile.isLoggedIn ? "重新登录" : "登录", action: login)
                    .disabled(isBusy)
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新额度")
                .disabled(isBusy)
                Button(isActive ? "更改模式" : "切换账号", action: switchProfile)
                    .disabled(isBusy)
                    .buttonStyle(.borderedProminent)
                Menu {
                    Button("删除账号配置", role: .destructive, action: deleteProfile)
                        .disabled(isActive || isBusy)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .font(.caption)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green.opacity(0.55) : Color.secondary.opacity(0.18), lineWidth: isActive ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }

    private var loginState: (title: String, color: Color) {
        guard profile.isLoggedIn else { return ("未完成登录", .orange) }
        if quota?.stale == true,
           quota?.errorMessage?.localizedCaseInsensitiveContains("登录") == true {
            return ("登录已失效", .red)
        }
        if profile.accountEmail != nil { return ("已绑定", .green) }
        return ("待验证", .orange)
    }

    @ViewBuilder
    private func freshness(_ quota: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(quota.email ?? "未读取到账号邮箱")
                Spacer()
                Text(quota.stale ? "刷新失败，显示上次数据" : "更新于 \(quota.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(quota.stale ? .orange : .secondary)
            }
            if quota.stale, let errorMessage = quota.errorMessage {
                Text(errorMessage)
                    .lineLimit(2)
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2)
    }
}

private struct RenewalSummary: View {
    let profile: CodexProfile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.secondary)
            if let day = profile.renewalDay {
                Text("每月 \(day) 日续费")
                Text("下次：\(nextRenewalText(day: day))")
                    .foregroundStyle(.secondary)
                if !profile.reminderDays.isEmpty {
                    Text("提醒：\(profile.reminderDays.sorted(by: >).map { "\($0)天前" }.joined(separator: "、"))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未设置续费日期")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func nextRenewalText(day: Int) -> String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: Date())
        for offset in 0...2 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(day, range.count)
            components.hour = 9
            if let candidate = calendar.date(from: components), candidate >= start {
                return candidate.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return "未知"
    }
}

private struct QuotaRow: View {
    let label: String
    let window: RateLimitWindow?

    var body: some View {
        HStack {
            Text(label).frame(width: 55, alignment: .leading)
            ProgressView(value: Double(window?.remainingPercent ?? 0), total: 100)
            Text(window.map { "\($0.remainingPercent)%" } ?? "未知")
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            Text(window?.resetDate?.formatted(date: .omitted, time: .shortened) ?? "")
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct AddProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "#4F7CAC"
    @State private var renewalDay = ""
    let save: (String, String, Int?) -> Void

    var body: some View {
        Form {
            Text("添加 Codex 账号").font(.headline)
            TextField("账号备注（可选），例如：工作账号", text: $name)
            TextField("标识颜色，例如：#4F7CAC", text: $color)
            TextField("每月续费日，可选，填写 1-31", text: $renewalDay)
            Text("创建后会打开官方 codex login。登录完成并刷新后，软件会自动绑定并显示真实 Codex 账号；这里填写的名称仅作为辅助备注。凭据只保存在该账号独立的 CODEX_HOME 中。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建并登录") { save(name, color, Int(renewalDay)) }
            }
        }
        .padding()
        .frame(width: 420)
    }
}

private struct LoginCommandView: View {
    @Environment(\.dismiss) private var dismiss
    let login: LoginCommand
    let completed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("请完成 \(login.profileName) 的官方登录")
                .font(.title3.bold())
            Text("我已经尝试打开终端执行登录命令，并把命令复制到了剪贴板。如果终端没有打开，请打开 Terminal，粘贴下面命令并回车。")
                .foregroundStyle(.secondary)
            Text(login.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("登录成功的标志：浏览器授权完成后，codex login 结束并自动退出；回到本软件刷新后，会显示真实 Codex 账号并标记为“已绑定”。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("复制命令") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(login.command, forType: .string)
                }
                Spacer()
                Button("关闭") { dismiss() }
                Button("我已完成登录，立即刷新") {
                    completed()
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

private struct SwitchConfirmationView: View {
    let request: SwitchRequest
    let activeProfile: CodexProfile?
    let confirm: (CodexSwitchMode, Bool, Bool) -> Void
    let preflight: (CodexSwitchMode, Bool) -> Void
    let cancel: () -> Void

    @State private var mode: CodexSwitchMode
    @State private var rememberAsDefault = true
    @State private var initializeSharedFromCurrent = false

    init(
        request: SwitchRequest,
        activeProfile: CodexProfile?,
        confirm: @escaping (CodexSwitchMode, Bool, Bool) -> Void,
        preflight: @escaping (CodexSwitchMode, Bool) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.request = request
        self.activeProfile = activeProfile
        self.confirm = confirm
        self.preflight = preflight
        self.cancel = cancel
        _mode = State(initialValue: request.selectedMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("切换到 \(request.profile.displayName)").font(.title2.bold())
                    Text("选择这次启动时，账号之间如何使用项目、对话与配置。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "rectangle.2.swap")
                    .font(.largeTitle)
                    .foregroundStyle(mode.tint)
            }

            VStack(spacing: 8) {
                ForEach(CodexSwitchMode.allCases) { mode in
                    ModeChoiceRow(mode: mode, isSelected: self.mode == mode) {
                        self.mode = mode
                    }
                }
            }

            if mode == .sharedState {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("首次使用时，以当前账号内容初始化共享空间", isOn: $initializeSharedFromCurrent)
                        .disabled(activeProfile == nil)
                    Text("仅首次需要。之后所有共享状态账号都会使用同一套项目与对话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Toggle("设为 \(request.profile.displayName) 的默认模式", isOn: $rememberAsDefault)

            HStack {
                Button("模拟预检") {
                    preflight(mode, initializeSharedFromCurrent)
                }
                .help("只检查认证、运行中任务和状态准备逻辑，不停止或启动 Codex")
                Spacer()
                Button("取消") { cancel() }
                Button("使用\(mode.title)切换") {
                    confirm(mode, rememberAsDefault, initializeSharedFromCurrent)
                }
                .buttonStyle(.borderedProminent)
                .tint(mode.tint)
            }
        }
        .padding(18)
        .background(.background)
    }
}

private struct ModeChoiceRow: View {
    let mode: CodexSwitchMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(mode.tint)
                    .frame(width: 36, height: 36)
                    .background(mode.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(mode.audience)
                            .font(.caption2.bold())
                            .foregroundStyle(mode.tint)
                    }
                    Text(mode.shortSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text(mode.dataBoundary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? mode.tint : Color.secondary.opacity(0.45))
            }
            .padding(11)
            .contentShape(Rectangle())
            .background(
                isSelected ? mode.tint.opacity(0.08) : Color.secondary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? mode.tint.opacity(0.7) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModeBadge: View {
    let mode: CodexSwitchMode
    let prefix: String

    var body: some View {
        Label("\(prefix) · \(mode.title)", systemImage: mode.icon)
            .font(.caption2.bold())
            .foregroundStyle(mode.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(mode.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct OperationLogView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [OperationLogEntry]
    let refresh: () -> Void
    let openDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("操作日志").font(.title2.bold())
                    Text("最近 \(entries.count) 条操作、状态和错误记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新", action: refresh)
                Button("打开日志目录", action: openDirectory)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if entries.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(entry.level.title)
                                .font(.caption2.bold())
                                .foregroundStyle(entry.level.color)
                            Text(entry.event)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption)
                        if let profileName = entry.profileName {
                            Text("账号：\(profileName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let durationMs = entry.durationMs {
                            Text("耗时：\(durationMs) ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let errorMessage = entry.errorMessage {
                            Text("错误：\(errorMessage)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                        }
                        if !entry.metadata.isEmpty {
                            Text(entry.metadataText)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .frame(width: 760, height: 560)
    }
}

private struct RenewalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: CodexProfile
    let save: (Int?, [Int]) -> Void

    @State private var enabled: Bool
    @State private var day: Int
    @State private var reminder7: Bool
    @State private var reminder3: Bool
    @State private var reminder1: Bool

    init(profile: CodexProfile, save: @escaping (Int?, [Int]) -> Void) {
        self.profile = profile
        self.save = save
        _enabled = State(initialValue: profile.renewalDay != nil)
        _day = State(initialValue: profile.renewalDay ?? 1)
        _reminder7 = State(initialValue: profile.reminderDays.contains(7))
        _reminder3 = State(initialValue: profile.reminderDays.contains(3))
        _reminder1 = State(initialValue: profile.reminderDays.contains(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("续费设置").font(.title2.bold())
                    Text(profile.displayName).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
            }

            Toggle("记录这个账号的月度续费日", isOn: $enabled)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("每月")
                    Picker("续费日", selection: $day) {
                        ForEach(1...31, id: \.self) { value in
                            Text("\(value) 日").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!enabled)
                    Text("续费")
                }
                if enabled {
                    Text("如果某个月没有 \(day) 日，会自动按当月最后一天计算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("下次续费：\(nextRenewalText(day: day))")
                        .font(.headline)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("本地提醒").font(.headline)
                Toggle("提前 7 天提醒", isOn: $reminder7).disabled(!enabled)
                Toggle("提前 3 天提醒", isOn: $reminder3).disabled(!enabled)
                Toggle("提前 1 天提醒", isOn: $reminder1).disabled(!enabled)
            }

            HStack {
                Button("清除续费日期") {
                    save(nil, [])
                    dismiss()
                }
                .disabled(!enabled)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存设置") {
                    save(enabled ? day : nil, enabled ? selectedReminders : [])
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var selectedReminders: [Int] {
        [(7, reminder7), (3, reminder3), (1, reminder1)]
            .compactMap { $0.1 ? $0.0 : nil }
    }

    private func nextRenewalText(day: Int) -> String {
        let service = RenewalPreviewCalculator()
        return service.nextRenewalDate(day: day)?.formatted(date: .complete, time: .omitted) ?? "未知"
    }
}

private struct RenewalPreviewCalculator {
    func nextRenewalDate(day: Int, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let start = calendar.startOfDay(for: date)
        for offset in 0...2 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(day, range.count)
            components.hour = 9
            if let candidate = calendar.date(from: components), candidate >= start {
                return candidate
            }
        }
        return nil
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Codex 多账号管理器")
                .font(.headline)
            Text("账号配置和操作日志保存在本机。登录凭据仍由官方 Codex CLI 管理。")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420)
    }
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("如何配置两个账号").font(.title2.bold())
            Group {
                Text("1. 点击主界面右上角的 +，可填写辅助备注，然后点击“创建并登录”。")
                Text("2. 终端会运行官方 codex login；如果没有打开，直接在终端粘贴剪贴板里的命令。")
                Text("3. 回到本应用点击“刷新额度”，软件会绑定并显示真实 Codex 登录账号。")
                Text("4. 再次点击 +，使用第二个 ChatGPT Plus 账号完成登录。")
                Text("5. 刷新第二个账号，确认两个 Profile 绑定的是不同的真实 Codex 账号。")
                Text("6. 日常切换时点击目标账号的“切换”，选择切换模式；不确定时先点“模拟预检”。如果当前账号有运行中任务，软件会阻止切换。")
            }
            .font(.body)
            Divider()
            Text("提示：浏览器可能自动使用当前 ChatGPT 登录状态。配置第二个账号时，请先在浏览器确认或切换到第二个账号，再完成授权。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("知道了") { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private extension Color {
    init(hex: String) {
        let value = Int(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x4F7CAC
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private extension CodexSwitchMode {
    var icon: String {
        switch self {
        case .isolated: "person.crop.square"
        case .sharedState: "rectangle.3.group"
        case .partialShared: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .isolated: .blue
        case .sharedState: .green
        case .partialShared: .orange
        }
    }

    var shortSummary: String {
        switch self {
        case .isolated: "每个账号保留自己的项目、对话与配置"
        case .sharedState: "所有账号看到相同的项目、对话与配置"
        case .partialShared: "共享工具配置，项目与对话按账号独立"
        }
    }

    var audience: String {
        switch self {
        case .isolated: "边界最清晰"
        case .sharedState: "切换最连贯"
        case .partialShared: "推荐平衡"
        }
    }

    var dataBoundary: String {
        switch self {
        case .isolated:
            "独立：账号凭据、项目、对话、工具配置、日志"
        case .sharedState:
            "共享：项目、对话、工具配置、日志；独立：账号凭据"
        case .partialShared:
            "共享：工具、skills、prompts；独立：账号凭据、项目、对话、日志"
        }
    }
}

private extension OperationLogEntry.Level {
    var title: String {
        switch self {
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        }
    }

    var color: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

private extension OperationLogEntry {
    var metadataText: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }
}
