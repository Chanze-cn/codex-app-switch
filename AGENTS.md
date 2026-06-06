# Project Memory

- After completing any requested iteration task, do not bump the app version or commit/push automatically.
- First summarize the completed work, testing, and proposed next version.
- Ask the maintainer to confirm the version number.
- Only after confirmation, update version metadata, update the changelog if needed, commit, and push to GitHub.
- Prefer the smallest SemVer bump. UI refinements, dashboard/help iterations, packaging fixes, and documentation updates normally use a patch bump.
- Before publishing a new version, package the app and verify that `Build/CodexProfileManager.app` can launch successfully, including direct executable launch or `open -n`, so dynamic framework/signing issues are caught before release.
