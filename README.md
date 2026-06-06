# Codex Profile Manager

English | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

A native macOS menu bar app for managing multiple Codex account profiles with
isolated `CODEX_HOME` directories, quota visibility, switch preflight checks,
and renewal reminders.

> This project is an independent local helper. It does not bypass Codex or
> OpenAI account limits, and it does not replace the official `codex login`
> flow.

## Overview

Codex Profile Manager is built for users who legitimately use more than one
Codex-capable account and want a safer way to switch the local Codex Desktop
runtime between them.

Instead of repeatedly running `codex logout` and `codex login`, the app creates
one local profile per account. Each profile owns its own `CODEX_HOME`, so OAuth
credentials and account-specific state can stay separated. When switching, the
app validates the target profile, checks for running tasks, prepares the desired
state-sharing mode, stops Codex Desktop, and relaunches it with the selected
runtime environment.

## Features

- Native macOS SwiftUI menu bar app.
- Multiple Codex profiles, each backed by an independent `CODEX_HOME`.
- Official login flow launcher for each profile.
- Real account binding after quota refresh, using the account returned by Codex.
- Live quota snapshots for primary and secondary rate-limit windows.
- Three switch modes:
  - **Isolated**: account, threads, projects, tools, and config stay in the
    profile's own `CODEX_HOME`.
  - **Shared State**: accounts share one local Codex state directory while the
    selected account credentials are copied in during switch.
  - **Partial Shared**: account credentials and threads stay isolated, while
    config, tools, skills, prompts, themes, rules, MCP config, and hooks are
    synchronized.
- Switch preflight to validate auth, identity, state preparation, and local
  context preservation expectations before changing the active account.
- Active-task guard that blocks switching if the current Codex account appears
  to have running tasks.
- Renewal-day reminders with configurable reminder offsets.
- Operation logs and audit logs stored locally for troubleshooting.
- Packaging script for a signed local `.app` bundle.

## What Problem It Solves

Codex Desktop and the official CLI are designed around a single active local
runtime home. That is simple, but inconvenient when you need to keep two
accounts cleanly separated.

This app focuses on three practical goals:

1. Keep credentials isolated per account.
2. Make switching explicit and reversible enough to avoid losing local context.
3. Surface quota and renewal signals near the workflow where they matter.

## Requirements

- macOS 14 or later.
- Swift 6.1 toolchain.
- Codex Desktop installed as `Codex.app`.
- Official `codex` CLI available in `PATH`, `/opt/homebrew/bin`, or
  `/usr/local/bin`.

## Build

Run the self-tests:

```sh
Scripts/run_self_tests.sh
```

Build with Swift Package Manager:

```sh
swift build
```

Build a local `.app` bundle:

```sh
Scripts/package_app.sh
```

The packaged app is written to:

```text
Build/CodexProfileManager.app
```

## Usage

### 1. Create a Profile

Open the app and click `+`.

You can enter an optional display name, color, and monthly renewal day. The app
creates a new profile directory and opens the official `codex login` command in
Terminal with that profile's `CODEX_HOME`.

After the browser authorization completes, the login command exits
automatically. Return to the app and refresh quota to bind the profile to the
real Codex account email.

### 2. Add Additional Accounts

Repeat the same flow for each account. Each profile receives a separate local
directory:

```text
~/Library/Application Support/CodexProfileManager/Profiles/<profile-id>/
```

The app treats a profile as logged in when its profile home contains an
`auth.json` created by the official Codex login flow.

### 3. Refresh Quota

Use refresh to fetch quota information for each profile. Refresh also binds the
profile to the real account identity returned by Codex, which helps prevent
accidentally reusing the same account in multiple profile cards.

### 4. Switch Accounts

Click the target profile's switch action and choose a mode.

Before the switch completes, the app:

- validates the target profile home;
- verifies the target profile is logged in;
- checks that the target account identity matches the bound profile;
- checks recent Codex threads for active/running work;
- prepares state according to the selected switch mode;
- stops Codex Desktop;
- relaunches Codex Desktop with the selected `CODEX_HOME`.

Use preflight when you want to see what will happen without stopping or
relaunching Codex.

## Switch Modes

### Isolated

The safest mode. Codex Desktop launches with the target profile's own
`CODEX_HOME`.

Use this when account separation matters more than preserving local thread or
project context across accounts.

### Shared State

Codex Desktop launches with a shared `CODEX_HOME` managed by this app. During
switch, the selected account's auth file is copied into that shared state.

This can preserve more local project and thread state, but remote thread reuse
across accounts still depends on Codex behavior and is not guaranteed.

### Partial Shared

Codex Desktop launches with the target profile's own `CODEX_HOME`, but selected
configuration and customization files are synchronized from a shared area.

Currently shared items include:

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

Use this when you want accounts and conversations isolated, while keeping tools
and preferences consistent.

## Data Storage

By default, app data is stored under:

```text
~/Library/Application Support/CodexProfileManager/
```

Important paths:

```text
Profiles/              Per-account CODEX_HOME directories
SharedCodexHome/       Runtime home used by shared-state mode
PartialSharedState/    Shared config/tool state for partial-shared mode
profiles.json          Profile metadata
quota-cache.json       Cached quota snapshots
audit.jsonl            High-level audit events
operations.jsonl       Detailed operation logs
```

For tests or local development, the root can be overridden with:

```sh
CODEX_PROFILE_MANAGER_ROOT=/tmp/codex-profile-manager-dev
```

## Safety Model

- OAuth login is performed by the official `codex login` command.
- Credentials remain local and are stored in profile-specific `CODEX_HOME`
  directories.
- Direct account switching is blocked when active Codex tasks are detected or
  when the app cannot confirm that switching is safe.
- Profile identity is validated against the account returned by Codex to reduce
  accidental account mix-ups.
- Local app directories are created with restrictive permissions where possible.
- The app does not rotate accounts automatically and does not attempt to bypass
  quotas or usage limits.

## Current Limitations

- Each account must complete the official login flow at least once.
- Remote Codex threads are not migrated between accounts.
- Shared-state mode can preserve local state, but it cannot guarantee that a
  remote thread is usable from a different account.
- If active-task detection cannot confirm a safe switch, the app blocks the
  switch instead of guessing.
- The app expects Codex Desktop and the Codex CLI to be installed locally.

## Project Structure

```text
Sources/CodexProfileManager/
  AppModel.swift                 Main app state and workflow orchestration
  CodexLauncher.swift            Login, stop, and launch integration
  CodexStateCoordinator.swift    Isolated/shared/partial state preparation
  CodexAppServerClient.swift     Codex account, quota, and thread queries
  ProfileStore.swift             Profile and quota persistence
  RenewalReminderService.swift   Local renewal notifications
  MainView.swift                 SwiftUI interface
  Models.swift                   Shared data models
  Paths.swift                    Runtime path and environment helpers
  OperationLogger.swift          Local operation logs

Scripts/
  run_self_tests.sh              Lightweight self-test runner
  package_app.sh                 Local app bundle packaging script
  generate_icon.swift            App icon generation helper

Tests/SelfTests/
  main.swift                     Self-tests for model/state behavior
```

## Development

Recommended checks before committing:

```sh
Scripts/run_self_tests.sh
swift build
```

The self-test script compiles the core model and state-management files into a
temporary binary and runs behavioral checks without writing to the user's real
Codex profile data.

## Support and Contact

If this project saves you time, you can support the author by buying a coffee.
Alipay and WeChat Pay QR codes can be placed under `docs/assets/` and linked
from this section.

For questions, bug reports, or private feedback, contact:
[781830133@qq.com](mailto:781830133@qq.com).

## License

No license has been selected yet. Add a `LICENSE` file before publishing if you
want others to use, modify, or redistribute the project under explicit terms.
