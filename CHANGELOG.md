# Changelog

All notable project changes should be recorded here.

This project follows the versioning policy in [docs/VERSIONING.md](docs/VERSIONING.md).

## [Unreleased]

## [0.3.4] - 2026-06-06

### Fixed

- Ensured Sparkle update relaunch cleans up older app instances and disabled automatic background update installation so restart remains user-confirmed.

## [0.3.3] - 2026-06-06

### Fixed

- Fixed local ad-hoc packaged apps failing to launch after Sparkle integration because hardened runtime library validation rejected the embedded Sparkle framework signature.

## [0.3.2] - 2026-06-06

### Added

- Added Sparkle-based in-app update checking from the `更多` menu.
- Added GitHub Actions release automation that builds, packages, signs Sparkle appcasts, and uploads release assets.
- Added auto-update setup documentation and project memory for version confirmation before release commits.

### Changed

- Updated the packaging script to embed Sparkle.framework and support configurable signing identities.

## [0.3.1] - 2026-06-06

### Added

- Added a dashboard page that summarizes total weekly quota, total 5-hour quota, nearest reset times, latest refresh time, account coverage, and stale quota counts.

### Changed

- Reworked quota rows with clearer labels, explanatory copy, remaining percentages, and full reset date/time for both weekly and 5-hour windows.
- Added a main segmented view switch between the quota dashboard and account management list.

## [0.3.0] - 2026-06-06

### Added

- Added a periodic active-account verification loop that reads the real Codex runtime account and corrects or clears stale active-profile markers.
- Expanded in-app help with onboarding steps, switch-mode guidance, and Q&A.
- Added README guidance for common setup, switching, quota, and troubleshooting questions.

### Changed

- Refined the main SwiftUI interface with a more polished macOS-style header, account cards, status pills, and quota summaries.
- Weekly quota reset now displays the reset date instead of only a time of day.

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
