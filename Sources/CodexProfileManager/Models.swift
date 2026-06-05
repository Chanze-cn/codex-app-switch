import Foundation

struct CodexProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var accountEmail: String?
    var colorHex: String
    var codexHome: String
    var defaultSwitchMode: CodexSwitchMode
    var renewalDay: Int?
    var reminderDays: [Int]
    var lastUsedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        accountEmail: String? = nil,
        colorHex: String = "#4F7CAC",
        codexHome: String,
        defaultSwitchMode: CodexSwitchMode = .isolated,
        renewalDay: Int? = nil,
        reminderDays: [Int] = [7, 3, 1],
        lastUsedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.accountEmail = accountEmail
        self.colorHex = colorHex
        self.codexHome = codexHome
        self.defaultSwitchMode = defaultSwitchMode
        self.renewalDay = renewalDay
        self.reminderDays = reminderDays
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case accountEmail
        case colorHex
        case codexHome
        case defaultSwitchMode
        case renewalDay
        case reminderDays
        case lastUsedAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        codexHome = try container.decode(String.self, forKey: .codexHome)
        defaultSwitchMode = try container.decodeIfPresent(CodexSwitchMode.self, forKey: .defaultSwitchMode) ?? .isolated
        renewalDay = try container.decodeIfPresent(Int.self, forKey: .renewalDay)
        reminderDays = try container.decodeIfPresent([Int].self, forKey: .reminderDays) ?? [7, 3, 1]
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

extension CodexProfile {
    var displayName: String {
        accountEmail ?? name
    }

    var alias: String? {
        guard accountEmail != nil, name.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return name
    }

    var isLoggedIn: Bool {
        FileManager.default.fileExists(atPath: URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json").path)
    }
}

enum CodexSwitchMode: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case isolated
    case sharedState
    case partialShared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isolated: "完全独立"
        case .sharedState: "共享状态"
        case .partialShared: "部分共享"
        }
    }

    var summary: String {
        switch self {
        case .isolated:
            "账号、项目、线程、配置都保存在这个账号自己的 CODEX_HOME。"
        case .sharedState:
            "所有账号共用同一套项目、线程、配置，只在切换时替换账号凭据。"
        case .partialShared:
            "账号、线程、聊天独立；配置、工具、skills、prompts 等保持共享。"
        }
    }
}

struct RateLimitWindow: Codable, Hashable, Sendable {
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Int?

    var remainingPercent: Int { min(100, max(0, 100 - usedPercent)) }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
}

struct CreditsSnapshot: Codable, Hashable, Sendable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct QuotaSnapshot: Codable, Hashable, Sendable {
    var email: String?
    var planType: String?
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
    var credits: CreditsSnapshot?
    var fetchedAt: Date
    var stale: Bool
    var errorMessage: String?

    var lowestRemainingPercent: Int? {
        [primary?.remainingPercent, secondary?.remainingPercent].compactMap { $0 }.min()
    }
}

struct HandoffPackage: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var sourceProfileID: UUID?
    var targetProfileID: UUID
    var workspacePath: String
    var gitBranch: String?
    var threadID: String?
    var summary: String
    var notes: String
    var unfinishedItems: [String]
    var createdAt: Date

    var prompt: String {
        """
        请继续处理从另一个 Codex 账号交接过来的任务。

        项目目录：\(workspacePath)
        Git 分支：\(gitBranch ?? "未知")
        原线程：\(threadID ?? "不可用")

        任务摘要：
        \(summary.isEmpty ? "未提供摘要。" : summary)

        用户备注：
        \(notes.isEmpty ? "未提供备注。" : notes)

        未完成事项：
        \(unfinishedItems.isEmpty ? "- 检查项目现状并确定下一步。" : unfinishedItems.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}

struct AuditEntry: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case profileCreated
        case loginStarted
        case quotaRefreshed
        case switchStarted
        case switchCompleted
        case switchFailed
        case handoffCreated
        case profileDeleted
    }

    var id = UUID()
    var kind: Kind
    var profileID: UUID?
    var message: String
    var createdAt = Date()
}

struct OperationLogEntry: Codable, Identifiable, Hashable, Sendable {
    enum Level: String, Codable, Sendable, CaseIterable {
        case info
        case warning
        case error
    }

    var id = UUID()
    var level: Level
    var event: String
    var profileID: UUID?
    var profileName: String?
    var message: String
    var metadata: [String: String]
    var durationMs: Int?
    var errorMessage: String?
    var createdAt = Date()
}

struct ThreadSummary: Sendable {
    var id: String
    var cwd: String?
    var title: String?
    var status: String?
}
