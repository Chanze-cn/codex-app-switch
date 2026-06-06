# Branching and Contribution Workflow

This project uses a lightweight GitHub Flow model with explicit branch names.

## Permanent Branches

### `main`

`main` is the stable integration branch.

Rules:

- keep `main` buildable;
- merge only reviewed and tested work;
- release tags are created from `main`;
- do not commit experimental work directly to `main` unless it is a tiny owner-only maintenance change.

## Working Branches

Use short, descriptive branch names:

```text
feature/<short-description>
fix/<short-description>
docs/<short-description>
chore/<short-description>
release/vX.Y.Z
hotfix/<short-description>
```

Examples:

```text
feature/pinned-active-profile
fix/quota-cache-write
docs/versioning-policy
chore/update-icon
release/v0.2.0
hotfix/login-terminal-exit
```

## Branch Types

- `feature/*`: user-facing features or meaningful internal capabilities.
- `fix/*`: bug fixes.
- `docs/*`: documentation-only changes.
- `chore/*`: maintenance, scripts, packaging, metadata.
- `release/*`: release preparation, version bump, changelog finalization.
- `hotfix/*`: urgent fixes cut from `main`.

## Commit Style

Use concise imperative commit messages:

```text
Pin active profile above quota sorting
Add versioning policy
Fix quota cache writes on macOS
```

Avoid vague messages like:

```text
update
fix
changes
```

## Pull Request Standard

Every non-trivial change should include:

- what changed;
- why it changed;
- how it was tested;
- screenshots for UI changes when useful;
- linked issue or context when available.

## Merge Standard

Before merging:

1. Run relevant tests.
2. Confirm the change is scoped.
3. Confirm README/docs are updated when behavior changes.
4. Confirm version bump is needed only for release branches.

## Release Flow

1. Branch from `main`:

   ```sh
   git checkout -b release/vX.Y.Z
   ```

2. Update `VERSION`, `Support/Info.plist`, client info, and `CHANGELOG.md`.
3. Run release checks.
4. Merge to `main`.
5. Tag from `main`:

   ```sh
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```

6. Push `main` and the tag.

## Project Rule Going Forward

Future project work should follow this document unless the maintainer explicitly
chooses a different process for a specific change.
