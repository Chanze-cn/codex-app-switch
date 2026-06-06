# Versioning Policy

Codex Profile Manager uses a conservative SemVer-style version policy.

Current version: `0.3.5`

## Source of Truth

The project version is tracked in:

- `VERSION`
- `Support/Info.plist` as `CFBundleShortVersionString`
- `Support/Info.plist` as `CFBundleVersion` for the monotonically increasing macOS build number
- `Sources/CodexProfileManager/CodexAppServerClient.swift` client info when the app identifies itself to Codex
- `CHANGELOG.md`

When preparing a release, update all version references in the same commit.

## Version Format

Versions use:

```text
MAJOR.MINOR.PATCH
```

Examples:

- `0.1.0`
- `0.1.1`
- `0.2.0`
- `1.0.0`

## Bump Rules

### Patch: `0.2.1` -> `0.2.2`

Use a patch release for:

- bug fixes;
- safe UI copy adjustments;
- packaging fixes;
- documentation corrections that are shipped with a release;
- small internal improvements that do not change user workflows;
- incremental UI/dashboard/help iterations that refine existing account-management workflows.

### Minor: `0.2.1` -> `0.3.0`

Use a minor release for:

- a substantial new user-facing feature;
- a new switch mode or account-management workflow;
- a meaningful UI flow change that changes how users complete a workflow;
- a new supported platform/runtime requirement;
- changes that alter expected behavior but remain compatible with existing local data.

### Major: `0.x.y` -> `1.0.0`, then `1.x.y` -> `2.0.0`

Before `1.0.0`, the project is still stabilizing. Do not rush to `1.0.0`.

Use a major release for:

- breaking local data format changes;
- incompatible changes to profile storage;
- removal of a supported workflow;
- security model changes that require users to reconfigure accounts.

## Pre-1.0 Discipline

While the project is below `1.0.0`:

- prefer patch releases for fixes;
- use minor releases only for real feature milestones;
- do not bump the version for every README-only commit;
- collect related improvements into a single release when possible.

## Release Checklist

1. Confirm `main` is clean and all changes are merged.
2. Run:

   ```sh
   Scripts/run_self_tests.sh
   swift build
   ```

3. Package and verify the app can launch:

   ```sh
   Scripts/package_app.sh
   Build/CodexProfileManager.app/Contents/MacOS/CodexProfileManager
   open -n Build/CodexProfileManager.app
   ```

4. Update `VERSION`.
5. Update `Support/Info.plist`.
6. Increment `CFBundleVersion`.
7. Update client info version in `CodexAppServerClient.swift` if needed.
8. Update `CHANGELOG.md`.
9. Commit with:

   ```text
   Release vX.Y.Z
   ```

10. Tag the release:

   ```sh
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```

11. Push branch and tag:

   ```sh
   git push
   git push origin vX.Y.Z
   ```
