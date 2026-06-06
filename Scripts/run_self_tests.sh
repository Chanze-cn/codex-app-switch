#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/codex-profile-manager-self-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/codex-profile-manager-module-cache"
mkdir -p "$MODULE_CACHE"

swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Sources/CodexProfileManager/Models.swift" \
  "$ROOT/Sources/CodexProfileManager/JSONStore.swift" \
  "$ROOT/Sources/CodexProfileManager/Paths.swift" \
  "$ROOT/Sources/CodexProfileManager/OperationLogger.swift" \
  "$ROOT/Sources/CodexProfileManager/CodexStateCoordinator.swift" \
  "$ROOT/Sources/CodexProfileManager/RenewalReminderService.swift" \
  "$ROOT/Tests/SelfTests/main.swift" \
  -o "$OUT"
CODEX_PROFILE_MANAGER_DISABLE_LOGS=1 \
CODEX_PROFILE_MANAGER_ROOT="$OUT-root" \
"$OUT"
