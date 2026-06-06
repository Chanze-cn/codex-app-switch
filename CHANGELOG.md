# Changelog

All notable project changes should be recorded here.

This project follows the versioning policy in [docs/VERSIONING.md](docs/VERSIONING.md).

## [0.2.1] - 2026-06-06

### Fixed

- Made the active profile pinning state visually explicit in the profile card.
- Rebuilt the packaged app with the active-profile sorting behavior included.

## [0.2.0] - 2026-06-06

### Added

- Version source file and documented release policy.
- Branching and contribution workflow documentation.
- GitHub pull request template.
- Version display in the app settings view.

### Changed

- Active profile stays pinned at the top of the account list.

## [0.1.0] - 2026-06-06

### Added

- Native macOS menu bar app for managing multiple Codex profiles.
- Per-profile `CODEX_HOME` isolation.
- Official Codex login launcher.
- Quota refresh and account binding.
- Isolated, shared-state, and partial-shared switch modes.
- Switch preflight and active-task guard.
- Renewal reminders, operation logs, and audit logs.
- Multilingual README documents.
- Support/contact documentation and sponsor QR codes.
- MIT License.

### Fixed

- Quota cache writes use a macOS-safe atomic JSON write path.
