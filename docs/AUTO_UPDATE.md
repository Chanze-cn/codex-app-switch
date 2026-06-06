# Auto Update and Release Setup

Codex Profile Manager uses Sparkle 2 for in-app macOS updates and GitHub
Releases for hosting update archives and the Sparkle appcast.

## Runtime Flow

1. The app reads `SUFeedURL` from `Support/Info.plist`.
2. The user chooses `更多 -> 检查更新`.
3. Sparkle downloads `appcast.xml` from GitHub Releases.
4. Sparkle verifies the update archive with the `SUPublicEDKey` embedded in the
   app.
5. Sparkle installs the new app bundle and relaunches the app.

## Release Flow

Pushing a tag like `v0.3.2` triggers `.github/workflows/release.yml`.

The workflow:

1. Resolves Swift packages, including Sparkle.
2. Builds and packages `Build/CodexProfileManager.app`.
3. Optionally signs and notarizes with Developer ID credentials.
4. Creates `CodexProfileManager-<version>.zip`.
5. Signs the zip with Sparkle EdDSA.
6. Generates `appcast.xml`.
7. Uploads the zip and appcast to the GitHub Release.

## Required Secret

`SPARKLE_PRIVATE_KEY` is required for the GitHub release workflow to generate a
valid appcast.

The matching public key is stored in `Support/Info.plist` as `SUPublicEDKey`.
Never commit the private key.

To export the private key from the maintainer machine after generating it:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account codex-profile-manager -x /tmp/codex-profile-manager-sparkle-private-key.txt
```

Then add the file contents as the GitHub repository secret
`SPARKLE_PRIVATE_KEY`, and delete the temporary file.

## Optional Developer ID Secrets

For public distribution outside the developer's own machine, configure these
secrets so the release app is Developer ID signed and notarized:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID `.p12` certificate.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12` certificate.
- `KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `DEVELOPER_ID_APPLICATION`: signing identity name, for example
  `Developer ID Application: Example (TEAMID)`.
- `APPLE_ID_USERNAME`: Apple ID email for notarization.
- `APPLE_ID_PASSWORD`: app-specific password or notarization credential.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

If these are not present, the workflow can still create an ad-hoc signed app
for development testing, but that is not recommended for broad distribution.

## Version Discipline

Do not bump versions automatically after an implementation task. First confirm
the intended version with the maintainer. After confirmation, update version
metadata, commit, push, and tag.
