---
name: skill-aproda-aldc-release
description: "Prepare and release the Aproda ALDC layer or internal VS Code extension. Triggers on: Aproda release, layer version bump, vscode-ext tag, VSIX release, GitHub release, release approval, release notes, or release workflow. Fork-maintainer only; never sync to consumer projects."
---

# Skill: Aproda ALDC Release

> **Fork-maintainer only.** This skill governs releases of the Aproda ALDC fork and its internal VS Code extension. It is deliberately excluded from the project overlay. For layer architecture and change governance, load `skill-aproda-aldc` as well.

## Purpose

Prepare a reviewed release locally, then let GitHub Actions validate, tag, and publish it. A release tag is created only after the relevant checks pass and a maintainer approves the configured GitHub Environment.

## Release streams

| Stream | Version source | Tag | GitHub Release purpose |
|---|---|---|---|
| Aproda layer | `aldc.yaml` → `aproda.layerVersion` | `v<layerVersion>` | Internal release history and generated notes |
| VS Code extension | `tools/aproda-vscode-extension/package.json` → `version` | `vscode-ext/v<semver>` | Internal release history and the VSIX self-update asset |

Do not compare or reuse versions across streams. A layer release does not require a VSIX release, and vice versa.

## Before merge

1. Identify the changed stream. For a layer change, load `skill-aproda-aldc` and surface the relevant decision before changing the layer.
2. Increase the corresponding version exactly once.
3. Update the stream's changelog and relevant documentation:
   - Layer: `aldc.yaml`, `.github/readme.aproda.md`, `.github/decisions.aproda.md`, and the layer inventory when applicable.
   - Extension: `package.json`, `CHANGELOG.md`, README when installation or update behavior changes.
4. Run the applicable local validation and commit the complete release candidate.
5. Merge the reviewed candidate to the `aproda` branch.

## Automated release flow

1. A push to `aproda` with a new stream version starts the matching validation workflow.
2. The workflow checks that the candidate version is valid, has no existing tag, and is newer than the latest published version.
3. The workflow runs its validation suite. A failed suite never creates a tag.
4. The final job waits at its GitHub Environment approval gate.
5. After approval, the workflow creates and pushes the tag, then creates the GitHub Release with generated release notes.

Never create or push `v<layerVersion>` or `vscode-ext/v<semver>` manually. A tag means the candidate was validated and released by CI.

## Layer release checks

- The version matches `^<core>_aproda.<revision>$`.
- It is greater than the highest existing `v*_aproda.*` tag.
- `tools/aldc-validate` succeeds against the fork `aldc.yaml`.
- The tag points to the approved `aproda` commit.

The layer update mechanism consumes the Git tag. The GitHub Release has no required binary asset; it records the published version and release notes for maintainers.

## VS Code extension release checks

- `package.json` has a valid SemVer version.
- It is greater than the highest existing `vscode-ext/v*` tag.
- `npm ci`, `npm test`, and `npm run package` succeed in `tools/aproda-vscode-extension`.
- The release attaches `aproda-aldc-<semver>.vsix`.

The extension's self-update check resolves the tag, then downloads that VSIX asset from the matching GitHub Release. Do not approve the release if the asset upload is absent or failed.

## GitHub Environment setup

Repository administrators configure the approval policies outside Git:

- `aproda-layer-release`
- `aproda-vscode-extension-release`

In **Repository Settings → Environments**, configure the required reviewers for each environment. Without required reviewers, the final release job proceeds automatically.

## Constraints

- This is a release procedure, not a version-bumping tool. It never chooses a version or changes files without explicit maintainer intent.
- Keep releases on the `aproda` branch. Do not release an unmerged feature branch.
- This skill is fork-only and must remain excluded from `tools/aproda-sync/aproda-sync.json`.
- Do not publish, push tags, approve an Environment, or create a GitHub Release on behalf of the user without explicit confirmation.