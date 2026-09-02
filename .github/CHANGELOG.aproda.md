# Aproda ALDC Layer Changelog

> Curated release notes for the Aproda layer (`aldc.yaml` → `aproda.layerVersion`). The technical, per-commit record stays in the [Version / pin changelog](decisions.aproda.md#version--pin-changelog); this file is the human-readable summary maintained alongside each release, mirroring the style of [`tools/aproda-vscode-extension/CHANGELOG.md`](../tools/aproda-vscode-extension/CHANGELOG.md). See `skill-aproda-aldc-release` for when this file is updated.

## 1.2.0_aproda.17

- Ships the tiered AI translation workflow for XLIFF (E-005): Stage 0 (delegated AI batch translation with a PoEdit approval gate) and Stage 1 (deterministic invariant/project-memory resolution) are implemented and validated against a real BC app.
- Adds `tools/aproda-ps-xliffsync/` (D-31), wired into `skill-translate`'s Sync → Resolve → Export/Apply → Review → Validate workflow (D-32); documented in `readme.aproda.md` and `onboarding.aproda.md`.
- creates extension-backlog plan folders out of `.github/plans/` (reserved for the ALDC tool itself) into the new `_A-ALDC-Plans/{id}-{req_name}/` root folder, excluded from `aproda-sync` via `neverTouch`.

## 1.2.0_aproda.16

- Fixes BCQuality clone path casing: the workspace seed template and `Initialize-AprodaProject.ps1`'s fallback workspace writer now consistently use `../BCQuality-Aproda` (previously `bcquality-aproda` / `BCquality-Aproda`, mismatched casing across files).
- Aligns the workspace-folder display name to `BCQuality (Aproda ALDC)` in the fallback initializer, matching the seed template.
- Removes a stale, dead `.gitignore` entry (`Base/tools/bcquality-aproda/`) that never matched any generated path.

## 1.2.0_aproda.15

- Enforces exclusive `memory.md` lifecycle ownership: implementation subagents cannot mutate requirement status, and the Conductor rejects a phase result when its pre-review `memory.md` snapshot changes.
- Clarifies the HITL status contract: only delivery owners move a requirement to `review`; resolving all HITL issues keeps it in `review` until `al-pr-prepare` satisfies the Completion Gate.

## 1.2.0_aproda.14

- Adds `.github/audits/` and `.github/reports/` to the managed `.gitignore` block so review/report scratch folders stay untracked in consuming projects.

## 1.2.0_aproda.13

- Adds a completion-gate hardening for ADO work items: automatic title retrieval (`Get-AdoWorkItem.ps1`) when a work item has none, explicit human-approval scripts for creating/updating ADO pull requests and work items, and Azure CLI setup guidance in the extension's onboarding.
- Upgrades `al-pr-prepare`'s Completion Gate to a self-verified HARD GATE (D-26): required verification actions (`git status --short`, file-existence checks) and a mandatory ✅/❌ report, instead of a narrated checklist.
- Introduces this curated layer changelog (`CHANGELOG.aproda.md`, D-27) alongside the technical Version/pin changelog, and slims that changelog's `Notes` column to short technical keywords going forward.

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
