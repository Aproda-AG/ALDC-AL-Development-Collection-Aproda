# Aproda ALDC Layer Changelog

> Curated release notes for the Aproda layer (`aldc.yaml` → `aproda.layerVersion`). The technical, per-commit record stays in the [Version / pin changelog](decisions.aproda.md#version--pin-changelog); this file is the human-readable summary maintained alongside each release, mirroring the style of [`tools/aproda-vscode-extension/CHANGELOG.md`](../tools/aproda-vscode-extension/CHANGELOG.md). See `skill-aproda-aldc-release` for when this file is updated.

## 1.2.0_aproda.12

- Published the current approved Aproda toolkit state as the next CI-gated layer release revision.

## 1.2.0_aproda.11

- Opens the Aproda ALDC walkthrough directly from the first-run notification and applies the toolkit from its second step, using Toolkit terminology consistently.
- Restores the initial setup notification after resetting extension-owned local data without resetting VS Code walkthrough progress.

## 1.2.0_aproda.10

- Adds CI-gated release governance (D-25): the layer and VSIX release workflows validate candidates pushed to `aproda`, wait for GitHub Environment approval, then create their own tags and GitHub Releases.
- Adds the fork-only `skill-aproda-aldc-release`, excluded from overlay sync.
- The internal VS Code extension supports credential sign-in retry and versioned VSIX release assets.

## 1.2.0_aproda.9

- Re-pins all 10 agents off the retiring model to `Claude Sonnet 5` (doc-producing roles) and `GPT-5.6 Terra` (code/tool-loop/JSON roles).
- Adds a Model Escalation Gate to `al-architect` (HIGH complexity) and `al-triage` (high-stakes incident) — a HITL stop that recommends escalation without naming the running model.
- Migrates workflow prompts off the retiring model.

## 1.2.0_aproda.8

- Fixes tool-fit issues across agents: publisher casing, MCP server key naming.
- Rewrites `al-architect`'s CANNOT block to allow read-only terminal and subagent use for context-gathering, while still forbidding builds/deploys.

## 1.2.0_aproda.7

- Extends the `skill-aproda-ado` `req_name` pattern to `{type}-{id}-{short-name}`, with the short name derived from the work item title.
- Updates `al-pr-prepare` accordingly.

## 1.2.0_aproda.6

- Completes a sync-layer audit: brings the `aproda-sync.json` in-place-edits list and the D-7 register back in sync, and adds a stale-cleanup tombstone for the renamed `skill-ado` folder.

## 1.2.0_aproda.5

- Renames `skill-ado` to `skill-aproda-ado` for naming-convention compliance (Aproda-specific skills must carry the `skill-aproda-*` prefix so the allowlist glob picks them up automatically).

## 1.2.0_aproda.4

- Completes the technical rename started in `.3`: all file names, PowerShell identifiers, environment variables, and path references now consistently use "Deploy-Run-Verify" and "HITL Validation" instead of the retired "Test-Loop" / "UAT loop" terms.

## 1.2.0_aproda.3

- Renames "Test-Loop" to "Deploy-Run-Verify Cycle" and "UAT loop" to "HITL Validation" across docs, agents, skills, and instructions (display names only; technical identifiers followed in `.4`).

## 1.2.0_aproda.2

- Renames the BCQuality clone folder from `bcquality` to `bcquality-aproda`.
- Changes the layer-version scheme separator from `+` to `_` for URL-safety, and adds the release tagging rule.

## 1.2.0_aproda.1

- Initial Aproda layer setup; ALDC base commit recorded retroactively.
- Adopts the `<ALDC core.version>_aproda.<revision>` versioning scheme (D-17).
