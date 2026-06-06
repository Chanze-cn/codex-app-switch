# Codex Profile Manager

[English](README.md) | 简体中文 | [日本語](README.ja.md)

一个原生 macOS 菜单栏应用，用于管理多个 Codex 账号 Profile。它通过隔离
`CODEX_HOME`、展示额度信息、执行切换预检和配置续费提醒，让多账号使用变得
更清晰、更可控。

> 本项目是一个独立的本地辅助工具。它不会绕过 Codex 或 OpenAI 的账号限制，
> 也不会替代官方 `codex login` 登录流程。

## 项目概览

Codex Profile Manager 面向确实需要使用多个 Codex 可用账号的用户，目标是让
Codex Desktop 在不同本地运行环境之间切换时更安全。

与反复执行 `codex logout` / `codex login` 不同，本应用会为每个账号创建独立
Profile。每个 Profile 都有自己的 `CODEX_HOME`，因此 OAuth 凭据和账号相关状态
可以保持隔离。切换账号时，应用会验证目标 Profile、检查是否存在运行中的任务、
按选定模式准备状态、停止 Codex Desktop，并用目标运行环境重新启动 Codex。

## 功能特性

- 原生 macOS SwiftUI 菜单栏应用。
- 支持多个 Codex Profile，每个 Profile 对应独立 `CODEX_HOME`。
- 为每个 Profile 启动官方 `codex login` 登录流程。
- 刷新额度后绑定 Codex 返回的真实账号身份。
- 展示 primary / secondary rate-limit 窗口的实时额度快照。
- 支持三种切换模式：
  - **完全独立**：账号、线程、项目、工具和配置都保存在该 Profile 自己的
    `CODEX_HOME`。
  - **共享状态**：多个账号共用一个本地 Codex 状态目录，切换时写入目标账号凭据。
  - **部分共享**：账号凭据和线程保持独立，同时同步配置、工具、skills、prompts、
    themes、rules、MCP 配置和 hooks。
- 切换预检会在真正停止或重启 Codex 前验证认证、身份、状态准备和上下文保留预期。
- 检测到当前 Codex 账号可能存在运行中任务时，会阻止切换。
- 支持按续费日设置本地提醒和提醒提前天数。
- 本地保存操作日志和审计日志，便于排查问题。
- 提供脚本打包本地签名的 `.app`。

## 解决的问题

Codex Desktop 和官方 CLI 默认围绕一个本地运行目录工作。这个模型很简单，但在
需要清晰分隔多个账号时并不方便。

本应用关注三个实际目标：

1. 每个账号的凭据独立保存。
2. 账号切换必须明确，并尽量避免丢失本地上下文。
3. 在工作流附近展示额度和续费相关信息。

## 环境要求

- macOS 14 或更高版本。
- Swift 6.1 工具链。
- 已安装 Codex Desktop，也就是 `Codex.app`。
- 官方 `codex` CLI 可在 `PATH`、`/opt/homebrew/bin` 或 `/usr/local/bin` 中找到。

## 构建

运行自测：

```sh
Scripts/run_self_tests.sh
```

使用 Swift Package Manager 构建：

```sh
swift build
```

打包本地 `.app`：

```sh
Scripts/package_app.sh
```

打包结果位于：

```text
Build/CodexProfileManager.app
```

## 使用方法

### 1. 创建 Profile

打开应用并点击 `+`。

你可以填写可选的显示名称、颜色和每月续费日。应用会创建新的 Profile 目录，并
在 Terminal 中用该 Profile 的 `CODEX_HOME` 启动官方 `codex login` 命令。

浏览器授权完成后，登录命令会自动退出。回到应用刷新额度，即可把 Profile 绑定到
Codex 返回的真实账号邮箱。

### 2. 添加更多账号

每个账号重复同样流程。每个 Profile 都会得到一个独立本地目录：

```text
~/Library/Application Support/CodexProfileManager/Profiles/<profile-id>/
```

当 Profile 目录中存在官方 Codex 登录流程创建的 `auth.json` 时，应用会将其视为
已登录。

### 3. 刷新额度

点击刷新可获取每个 Profile 的额度信息。刷新也会绑定 Codex 返回的真实账号身份，
减少误把同一个账号绑定到多个 Profile 卡片的风险。

### 4. 切换账号

点击目标 Profile 的切换操作，并选择切换模式。

切换完成前，应用会：

- 验证目标 Profile 目录；
- 确认目标 Profile 已登录；
- 检查目标账号身份是否与已绑定 Profile 匹配；
- 检查最近 Codex 线程是否存在 active / running 任务；
- 根据所选切换模式准备状态；
- 停止 Codex Desktop；
- 使用目标 `CODEX_HOME` 重新启动 Codex Desktop。

如果你只想确认将发生什么，而不想停止或重启 Codex，可以先使用模拟预检。

## 切换模式

### 完全独立

最安全的模式。Codex Desktop 会使用目标 Profile 自己的 `CODEX_HOME` 启动。

当账号隔离比跨账号保留本地线程或项目上下文更重要时，建议使用该模式。

### 共享状态

Codex Desktop 会使用本应用管理的共享 `CODEX_HOME` 启动。切换时，应用会把目标
账号的 auth 文件复制到共享状态目录。

该模式可以保留更多本地项目和线程状态，但远程线程是否能跨账号继续使用，仍取决于
Codex 本身行为，不能保证。

### 部分共享

Codex Desktop 会使用目标 Profile 自己的 `CODEX_HOME` 启动，但选定的配置和自定义
内容会从共享区域同步。

当前同步项包括：

- `config.toml`
- `AGENTS.md`
- `AGENTS.override.md`
- `models_cache.json`
- `skills/`
- `plugins/`
- `prompts/`
- `themes/`
- `rules/`
- `mcp/`
- `hooks/`

当你希望账号和对话隔离，同时保持工具和偏好一致时，适合使用该模式。

## 数据存储

默认情况下，应用数据存储在：

```text
~/Library/Application Support/CodexProfileManager/
```

重要路径：

```text
Profiles/              每个账号的 CODEX_HOME 目录
SharedCodexHome/       共享状态模式使用的运行目录
PartialSharedState/    部分共享模式使用的配置和工具状态
profiles.json          Profile 元数据
quota-cache.json       缓存的额度快照
audit.jsonl            高层审计事件
operations.jsonl       详细操作日志
```

测试或本地开发时，可以通过环境变量覆盖根目录：

```sh
CODEX_PROFILE_MANAGER_ROOT=/tmp/codex-profile-manager-dev
```

## 安全模型

- OAuth 登录由官方 `codex login` 命令完成。
- 凭据保存在本机 Profile 独立的 `CODEX_HOME` 目录中。
- 检测到运行中 Codex 任务，或无法确认切换安全时，应用会阻止直接切换。
- 应用会用 Codex 返回的账号身份验证 Profile，降低账号混用风险。
- 本地应用目录会尽量使用限制性权限创建。
- 应用不会自动轮换账号，也不会尝试绕过额度或使用限制。

## 当前限制

- 每个账号都必须至少完成一次官方登录流程。
- 远程 Codex 线程不会在账号之间迁移。
- 共享状态模式可以保留本地状态，但无法保证远程线程能被另一个账号继续使用。
- 如果无法确认没有运行中任务，应用会阻止切换，而不是猜测。
- 应用要求本地已安装 Codex Desktop 和 Codex CLI。

## 项目结构

```text
Sources/CodexProfileManager/
  AppModel.swift                 应用状态和主要工作流编排
  CodexLauncher.swift            登录、停止和启动集成
  CodexStateCoordinator.swift    完全独立/共享/部分共享状态准备
  CodexAppServerClient.swift     Codex 账号、额度和线程查询
  ProfileStore.swift             Profile 和额度持久化
  RenewalReminderService.swift   本地续费提醒
  MainView.swift                 SwiftUI 界面
  Models.swift                   共享数据模型
  Paths.swift                    运行路径和环境变量辅助
  OperationLogger.swift          本地操作日志

Scripts/
  run_self_tests.sh              轻量自测脚本
  package_app.sh                 本地 app bundle 打包脚本
  generate_icon.swift            App 图标生成工具

Tests/SelfTests/
  main.swift                     模型和状态行为自测
```

## 开发

提交前建议运行：

```sh
Scripts/run_self_tests.sh
swift build
```

自测脚本会把核心模型和状态管理文件编译成临时二进制并运行行为检查，不会写入用户
真实的 Codex Profile 数据。

## 赞助与联系

如果这个项目帮你节省了时间，欢迎请作者喝一杯咖啡。支付宝和微信支付二维码可以
放在 `docs/assets/` 目录，并在本区块展示。

如果你遇到问题、想反馈 bug，或希望私下联系作者，可以发邮件到：
[781830133@qq.com](mailto:781830133@qq.com)。

## 许可证

当前尚未选择许可证。如果你希望他人可以明确地使用、修改或再分发本项目，请在发布前
添加 `LICENSE` 文件。
