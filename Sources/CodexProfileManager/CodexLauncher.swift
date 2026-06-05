import AppKit
import Foundation

struct CodexLauncher {
    enum LauncherError: LocalizedError {
        case codexAppNotFound
        case activeTasks
        case launchFailed

        var errorDescription: String? {
            switch self {
            case .codexAppNotFound: "未找到 Codex.app。"
            case .activeTasks: "当前账号仍有运行中的 Codex 任务。为避免丢失上下文，请等待任务完成后再切换。"
            case .launchFailed: "无法启动 Codex Desktop 或官方登录流程。"
            }
        }
    }

    func login(profile: CodexProfile) throws -> String {
        guard let executable = CodexExecutableLocator.locate() else { throw LauncherError.launchFailed }
        let exports = CodexRuntimeEnvironment.shellExports(codexHome: profile.codexHome, codexExecutable: executable)
        let command = "\(exports); \(shellQuote(executable)) login"
        let tmp = URL(fileURLWithPath: profile.codexHome).appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = tmp.appendingPathComponent("codex-login.command")
        let scriptBody = """
        #!/bin/zsh
        clear
        echo "正在为 Codex Profile 登录：\(profile.displayName)"
        echo "CODEX_HOME=\(profile.codexHome)"
        echo
        \(command)
        status=$?
        echo
        if [ "$status" -eq 0 ]; then
          echo "登录流程已结束。终端将自动退出，请回到 Codex 多账号管理器点击“刷新额度”。"
        else
          echo "登录命令退出码：$status"
          echo "你也可以复制下面命令手动执行："
          echo "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        fi
        echo
        exit "$status"
        """
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
        return command
    }

    func isDesktopRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty
    }

    func stopDesktop() async {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        apps.forEach { $0.terminate() }
        try? await Task.sleep(for: .seconds(2))
        apps.filter(\.isTerminated.not).forEach { $0.forceTerminate() }
    }

    func launch(profile: CodexProfile, workspacePath: String?) async throws {
        guard let codexAppURL = locateCodexApp() else { throw LauncherError.codexAppNotFound }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = CodexRuntimeEnvironment.environment(codexHome: profile.codexHome)
        var urls: [URL] = []
        if let workspacePath, !workspacePath.isEmpty {
            urls.append(URL(fileURLWithPath: workspacePath))
        }
        _ = try await NSWorkspace.shared.openApplication(at: codexAppURL, configuration: configuration)
        if let workspaceURL = urls.first {
            _ = try? await NSWorkspace.shared.open([workspaceURL], withApplicationAt: codexAppURL, configuration: configuration)
        }
    }

    private func locateCodexApp() -> URL? {
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            return registered
        }
        let fallback = URL(fileURLWithPath: "/Applications/Codex.app")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}

private extension Bool {
    var not: Bool { !self }
}
