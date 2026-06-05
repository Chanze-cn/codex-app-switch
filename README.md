# Codex Profile Manager

Native macOS menu bar app for managing isolated Codex profiles, live quota
visibility, renewal reminders, and task handoffs.

## 配置两个账号

1. 启动应用，点击右上角 `+`，可填写辅助备注并创建账号。
2. 在打开的终端和浏览器中完成第一个 ChatGPT Plus 账号的官方 Codex 登录。
3. 回到应用点击“刷新额度”，软件会绑定并显示真实 Codex 登录账号。
4. 再次点击 `+` 创建“账号 B”，登录第二个 ChatGPT Plus 账号。
5. 点击目标账号卡片中的“切换”，选择切换模式，必要时先点“模拟预检”，再确认切换。
6. 应用现在会显示在 Dock，并使用专用图标；窗口内和菜单栏入口都可以操作。

## 如何切换 Codex Mac 客户端账号

这个工具的目标是：每个账号只需要独立登录一次，之后在 Codex Mac 客户端中切换账号时，不再手动 `logout` / `login`。

### 首次准备

每个账号都必须先完成一次独立登录：

1. 在本工具中为账号 A 创建 Profile，并完成官方 `codex login`。
2. 为账号 B 创建另一个 Profile，并完成官方 `codex login`。
3. 两个账号卡片都显示真实 Codex 账号并标记“已绑定”后，才算准备完成。

每个 Profile 都有自己的独立 `CODEX_HOME`，登录凭据分别保存在：

```text
~/Library/Application Support/CodexProfileManager/Profiles/<profile-id>/
```

因此账号 A 和账号 B 的 Codex 登录状态不会互相覆盖。

### 日常切换

日常切换时不需要再手动退出登录或重新登录：

1. 确认目标账号卡片显示“已绑定”。
2. 在目标账号卡片点击“切换”。
3. 在确认面板中选择切换模式，必要时点击“模拟预检”。
4. 如果当前账号没有运行中的 Codex 任务，工具会按所选模式完成切换。

三种切换模式的上下文边界不同：

- `完全独立`：只把 Codex Mac 客户端指向目标账号自己的 `CODEX_HOME`。账号、项目、线程、聊天和配置都隔离；最安全，但不会保留当前账号上下文。
- `共享状态`：启动时使用工具维护的共享 `CODEX_HOME`，并把目标账号凭据放入该共享目录。它会尽量保留本地项目、线程和聊天状态；但远程线程是否能跨账号继续复用，仍取决于 Codex 官方能力，不能保证。
- `部分共享`：目标账号继续使用自己的 `CODEX_HOME`，只同步配置、工具、skills、prompts 等；聊天线程和项目状态仍按账号独立。

工具会自动执行：

- 检查当前账号是否有运行中的 Codex 任务。
- 如果检测到运行中任务，阻止切换，避免丢失上下文。
- 停止当前 Codex Mac 客户端。
- 按所选模式准备目标 `CODEX_HOME`：独立模式使用目标账号目录，共享状态使用共享目录，部分共享使用目标账号目录并同步配置。
- 将目标账号标记为当前账号。

也就是说，切换不是让你在 Codex Mac 客户端里手动 `logout` / `login`。工具会通过不同 `CODEX_HOME` 和所选模式准备启动环境，再拉起 Codex Mac 客户端。

如果你想确认这次切换会不会破坏上下文，先点“模拟预检”。预检只检查认证、运行中任务和状态准备结果，不会停止或启动 Codex，也不会改真实 Profile。

### 为什么之前要求填写项目目录和任务摘要

早期版本把“切换账号”和“任务交接”合并在一起，所以会要求填写项目目录、当前任务摘要和未完成事项。这些信息的作用是生成一份交接提示，让新账号在新线程里继续理解上下文。

现在日常切换不再要求填写这些信息。任务交接只适合在你确实想跨账号延续一个复杂任务时使用，不是普通切换账号的必要步骤。

### 当前限制

- 首次添加每个账号时仍然需要完成一次官方 `codex login`。
- 不会把旧账号的远程线程直接迁移到新账号。
- 普通切换不会要求填写项目目录或任务摘要。
- 如果当前账号有运行中的 Codex 任务，或者工具无法确认是否存在运行中任务，工具都会阻止切换。
- 如果目标账号显示“未完成登录”或“登录已失效”，切换前需要先点击“登录/重新登录”。
- 工具不会自动轮转账号，也不会绕过 Codex 或 OpenAI 的额度限制。

## Safety model

- Each account has an independent `CODEX_HOME`.
- OAuth credentials remain owned by the official `codex` CLI.
- Shared-state switching temporarily copies the selected profile's `auth.json`
  into the protected shared `CODEX_HOME`; credentials are never displayed or
  written to operation logs.
- Switching is always user initiated. There is no automatic rotation or quota pooling.

## Development

```bash
swift build
./Scripts/run_self_tests.sh
swift run CodexProfileManager
```

The app requires macOS 14+ and an official `codex` executable on `PATH`.
The self-test runner is framework-free because some Command Line Tools-only
installations do not ship `XCTest` or Swift Testing.

## Troubleshooting

### 刷新额度时报 `env: node: No such file or directory`

官方 `codex` CLI 可能是 `#!/usr/bin/env node` 脚本。终端里能运行
`codex`，不代表 macOS GUI 应用启动的环境也能找到 `node`，因为 GUI
应用不会自动加载你的 shell、nvm 或 Homebrew PATH。

本工具启动 `codex app-server` 时会显式补充常见 Node 路径，包括
`/opt/homebrew/bin`、`/usr/local/bin` 和 `~/.nvm/versions/node/*/bin`。
如果仍然报错，请确认 `node` 实际安装位置，并把它加入这些路径之一。

Build an unsigned local `.app` bundle:

```bash
./Scripts/package_app.sh
open ./Build/CodexProfileManager.app
```

## Profile storage

Application metadata is stored under:

```text
~/Library/Application Support/CodexProfileManager/
```

Individual Codex homes default to:

```text
~/Library/Application Support/CodexProfileManager/Profiles/<profile-id>/
```

These directories are created with owner-only permissions.
