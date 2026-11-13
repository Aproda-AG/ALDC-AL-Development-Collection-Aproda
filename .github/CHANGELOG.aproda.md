# Aproda ALDC Layer Changelog

> Curated release notes for the Aproda layer (`aldc.yaml` → `aproda.layerVersion`). The technical, per-commit record stays in the [Version / pin changelog](decisions.aproda.md#version--pin-changelog); this file is the human-readable summary maintained alongside each release, mirroring the style of [`tools/aproda-vscode-extension/CHANGELOG.md`](../tools/aproda-vscode-extension/CHANGELOG.md). See `skill-aproda-aldc-release` for when this file is updated.

## 1.2.0_aproda.18

> **Upgrade order:** install the Aproda ALDC extension **0.3.0 or newer** (released together: 0.3.2) before applying this layer. The workspace seed now mounts the virtual root `aldc-external:/`, which older extensions cannot serve.

- **BCQuality becomes a workstation property (E-006, D-49).** The clone location is resolved and probe-verified by the extension (user setting → mounted folder → `$BCQUALITY_HOME` → `<devRoot>/BCQuality-Aproda` → `aldc.yaml` `home`) and served to agents through the new `#bcquality` tool, with a documented direct-path fallback. Consumer `aldc.yaml` moves to `<toolkitRoot>` (`.github/aldc.yaml`, two-rung lookup, non-breaking); the tracked `.external/` wrapper with its README ships with the toolkit; `Migrate-AprodaProjectLayout.ps1` migrates existing projects (workspace file backed up before the first rewrite).
- **One constant virtual `.external` root (E-011, D-54).** External sources are served through `aldc-external:/` instead of a workspace root pointing at the clone; the junction is now optional. Init refreshes unmodified `.external/README.md` seeds and adds the root to existing workspace files.
- **Release channels (D-50).** `dualVariant` gains computed side injections (the delivered commit becomes part of the layer); update detection is channel-aware (`release`, `pinned`, `edge`, `branch`).
- **Deploy-Run-Verify:** missing target dependencies are detected by an adapter-agnostic preflight and resolved as an HITL offer with a confirmed-file-only install helper (D-51/D-52); HTTP 422 compile errors classify as *Rejected*; missing Microsoft test libraries install from the DVD; `alc.exe` is resolved lazily and version-ranked (`bin\alc.exe` and `bin\win32\alc.exe`); altool and ASINST remote-read failures are classified with readable reasons.
- **New skill `skill-aproda-al-mcp` (E-010, D-53):** Level-1 AL MCP access through `altool launchmcpserver` — one local target selection, SRP-safe starter, tool tiers; every publish goes through the Dev Endpoint.
- **New skill `skill-aproda-bc-data-access` (E-012, D-55):** read-only live data of a customer's BC SaaS environment for support/RCA through a session-lived helper app installed via the Automation API behind an identity guard; wired into `al-triage`.
- **Validation and sync tooling:** `aldc-validate` resolves `aldc.yaml` two-rung and gains the `agentToolCasing` rule (warn); both glob translators let `**/` span zero directories; the noise skip is depth-aware; `Test-InPlaceEditsRegister.ps1` verifies against a real `basePin` (corrected to the upstream merge-base `4f3371f`, E-006 T-16).
- **XLIFF:** strict-mode-safe consecutive-space check and version-aware `alc.exe` finder in `tools/aproda-ps-xliffsync/`; clarified German target rules in the translation subagent.
- **Agents and workflows:** model pins of 9 of 11 agents and several workflow prompts moved to Claude Sonnet 5.5 (`al-review-subagent` stays on GPT-5.6 Terra, `al-translate-subagent` on GPT-5.6 Luna); tool lists refreshed for semantic navigation, AL MCP and the new extension tools.
- Release checks: catalogs verified in sync (on disk = indexes = entrypoint: 11 agents, 23 skills, 12 workflows, 10 instructions); `agentToolCasing` 0 hits; `Test-InPlaceEditsRegister.ps1` 26/26 paths verified against `basePin`; `aldc-validate` COMPLIANT (2 known false-positive "ALDC Core v1.1" warnings from historical prose in `skill-aproda-aldc-release`).

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
