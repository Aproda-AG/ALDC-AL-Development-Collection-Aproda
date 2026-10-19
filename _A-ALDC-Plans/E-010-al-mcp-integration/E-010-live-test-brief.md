# E-010 — Live test brief (phases 2, 3, 4a, 4b)

**For:** the Copilot session in *Gustav Gerig AG Base* (environment access to TOGA and the Fkh container).
**Source of truth:** [`E-010.test-plan.md`](E-010.test-plan.md) (case IDs, expected results, safety rules §2),
[`E-010.spec.md`](E-010.spec.md). This brief only fixes order, preparation and reporting.
**Report to:** `Gustav Gerig AG Base/.github/documentation/ALDC/AlMcpE010Evidence.md` (new file, English), raw
`altool` captures to `.github/documentation/ALDC/altool-captures/` (scrubbed, see block D).

## Safety rules (binding, from test plan §2)

1. Targets: only `TOGA_FOOD_SA_28_AG_28_CH_FKO` (ASINST, `Windows`) and
   `flobi-wan-kenobi-gustavgerig-dev-deployment` (Fkh, `UserPassword`).
2. Environment acknowledgement by Florian once at the start of each block that writes to a target.
3. `ForceSync`, `forceUpgrade`, removals: only with the disposable app `E010 Recovery Probe`, each after its own
   confirmation. Never remove Base `25.0.0.156` (historical evidence).
4. No password, header, token or credential value in any output, file, capture or report.
5. Do not commit anything in the project. Temporary files under the ignored `Test/PowerShell/_temp/`.
6. A failed case: stop the block, report, wait. No workarounds in layer files — the engine and skills are
   immutable in the project; fixes happen in the fork.

## Block 0 — Preparation (Florian)

| Step | Action | Check |
|---|---|---|
| 0.1 | Fork: commit the E-010 implementation on the work branch (push optional). | `git status` clean except unrelated files |
| 0.2 | Project: Aproda extension settings `aprodaAldc.source.mode = localFork`, `aprodaAldc.source.forkPath = <fork path>`; then *Aproda ALDC: Check for Updates* / apply. A warning that the fork is not on `aproda` is expected. | `.github/skills/skill-aproda-al-mcp/` exists; `.github/skills/skill-aproda-deploy-run-verify/scripts/AprodaDeployRunVerify.psm1` contains `Invoke-DeployRunVerifyPublish` |
| 0.3 | Do **not** install the new extension yet (needed only in block C). | Extension version still `0.1.7` |
| 0.4 | Confirm the hand-copied pre-step engine files are overwritten by the pull. | hash of the engine = fork |

## Block A — DRV target selection (phase 4a) · no target writes

| Case | Steps | Expected |
|---|---|---|
| L-4a.1 | DRV `buildonly` with the **current** config (still contains `launchConfig`). | `CONFIG_MIGRATION_REQUIRED: launchConfig[,…]`, no connection |
| — | Migrate: `Set-AprodaAlLocalSelection -RepositoryRoot <repo> -LaunchProject Base -LaunchConfig <Fkh config name>` (library loaded content-based from `.github/skills/skill-aproda-al-mcp/scripts/AprodaAlTarget.ps1`); remove the target keys from `Test/deploy-run-verify.config.jsonc` (**local change, not committed**). | `.github/aldc.local.json` written, git-ignored (`git check-ignore`) |
| L-4a.3 | Temporarily point the selection at a non-existing configuration name; DRV `buildonly` then `full`. | `buildonly`: `TARGET: none (build-only)`; `full`: `TARGET_SELECTION_STALE` with the configuration list, no connection. Restore the selection. |

## Block B — `al-mcp` interim registration (phase 2)

Preparation: in `Base/.vscode/mcp.json` disable the prototype `al-mcp` entry locally (rename the key, do not
commit); create `.github/.vscode/mcp.json` with the snippet from `skill-aproda-al-mcp/SKILL.md` §9; reload.

| Case | Steps | Expected |
|---|---|---|
| L-2.1 | Rename `.github/aldc.local.json` temporarily; *MCP: Restart Server* `al-mcp`; `tools/list`; `al_compile` and `al_build` with `projectPath: Test` **after** `Update-AprodaAlPackageCache`. | MCP log `WARN SELECTION_ABSENT`, mode build-only; 16 tools; both green. **Records whether `pwsh` passes stdin/stdout through to `altool`** (the prototype used `powershell.exe`). |
| L-2.2 | Restore the selection (Fkh), restart; `al_run_tests` 59021 with the complete bundle from `Get-AprodaAlTargetBundle`. | 10/10; log without `CREDENTIAL_MISSING` |
| L-2.3 | Selection TOGA (`Windows`), restart; same call. | 10/10 |
| L-2.4 | Starter `-DryRun` in a terminal with `$env:LOCALAPPDATA` pointed at an empty temp folder, selection Fkh. | stderr `PLAN` with `mode: buildOnly`, reason `CREDENTIAL_MISSING`; stdout empty |
| L-2.5 | Starter `-DryRun` with the selection on a configuration that is **not** the first `server` entry of `Base/.vscode/launch.json`. | `WARN FIRST_CONFIG_DIFFERS Base`; mode unaffected |

## Block D — DRV routes (phase 4b) · writes to both targets

Acknowledgement by Florian before the block. Set `$env:APRODA_DEPLOY_RUN_VERIFY_*` variables per run and remove
them afterwards.

| Case | Target | Steps | Expected |
|---|---|---|---|
| L-4b.1 | TOGA | `full` | `ROUTE: build=altool · deploy=altool · tests=altool`; state verified; 23/23 |
| L-4b.2 | Fkh | `full` | same; no `fkh publishapp` in the log |
| L-4b.3 | TOGA | rebuild, then `skipbuild` with `DEPLOY_ROUTE=devEndpoint` | direct POST 200 with `DependencyPublishingOption=Default` (OS-2); state verified |
| L-4b.4 | Fkh | same as L-4b.3 | direct POST 200 over HTTPS; state verified |
| L-4b.5 | both | `runonly` with `TEST_ROUTE=altool`, then `TEST_ROUTE=webClient` | same verdict and 23 tests on both routes, both targets |
| L-4b.6 | both | `runonly` with the two server configurations in `Test/.vscode/launch.json` in **reversed** order (local scratch change, restore afterwards) | tests run on the **selected** target (OS-3) — check server/instance in the log |
| L-4b.7 | TOGA | `skipbuild` twice without rebuild | 2nd run `PUBLISH_DUPLICATE`, no direct POST, no second route |
| L-4b.8 | — | selection on a scratch configuration with a wrong port | altool `InvocationFailure` → direct POST `InvocationFailure` → stop; no target change |
| L-4b.9 | Fkh | wrong password in the store (Florian enters it), `full` | one re-prompt; right password → green + store updated; wrong again → `PUBLISH_AUTH_FAILED`, stop |
| L-4b.10 | TOGA | probe app with a removed field: `fkhSyncMode: Add`, then `ForceSync` (D-39: agent informs, no confirmation — but probe app only) | 1st `PUBLISH_REJECTED` with the schema message, no automatic escalation; 2nd `SCHEMA MODE: ForceSync (fkhSyncMode)`, green |
| L-4b.11 | TOGA | probe app in two versions; `Get-DeployRunVerifyCleanupCandidates`; remove the not-installed version after confirmation (`Remove-DeployRunVerifyAppVersion`) | candidate with full identity; installed version never a candidate; absence confirmed; afterwards remove the probe completely (Q-16 sequence) |
| L-4b.12 | both | capture the raw stdout/stderr of: `runtests` green (L-4b.5), `runtests` red (only if a naturally red test exists — otherwise skip and say so), `publishapp` success (L-4b.1), duplicate (L-4b.7), wrong port (L-4b.8), auth failure (L-4b.9), `altool --help` and `runtests --help` | one file per capture in `altool-captures/`, **scrubbed**: host names → `<host>`, instance → `<instance>`, user → `<user>`, no secrets; file names as in `tests/fixtures/altool/README.md` of the fork |

## Block C — Extension `0.2.0` (phase 3)

Preparation: remove `.github/.vscode/mcp.json` (interim); install
`tools/aproda-vscode-extension/dist/aproda-aldc-0.2.0.vsix` from the fork (*Extensions: Install from VSIX*);
reload. Florian performs the UI steps; the agent records.

| Case | Steps | Expected |
|---|---|---|
| L-3.8 | `aprodaAldc.alMcp.start = auto` (default). Reload Gustav, do not open chat. Second window with a non-AL folder. | Gustav: `al-mcp` running in *MCP: List Servers* before the first chat message; trust dialog once; non-AL window: no `al-mcp` |
| **Q-23** | If L-3.8 does not start the server by itself: note the exact server identifier VS Code shows (*MCP: List Servers*, MCP output channel name/log lines) and the Aproda ALDC log line `workbench.mcp.startServer failed …` if present. | identifier recorded (fork constant `ownServerIdCandidate` is a guess) |
| L-3.1 | *Select AL Target*: TOGA → Fkh → TOGA. | file rewritten each time; server restarts; **Q-24:** does the trust dialog reappear on each switch? |
| L-3.2 | Agent: `al_run_tests` 59021 with the bundle on each target. | 10/10 on both (Q-20 inside VS Code) |
| L-3.3 | Rename the stored Fkh credential file (Florian), restart the server. | notification *No stored credential …* → *Store credential* → terminal prompt → server restarts → L-3.2 green; delete the renamed file afterwards |
| L-3.4 | Chat: `#aldcConfiguration`; then with `aldc.local.json` renamed. | `local.state configured` + `targetBundle`; then `absent`, no bundle |
| L-3.9 | `aprodaAldc.alMcp.start = manual`, reload, send a chat message; then *Aproda ALDC: Start AL MCP Server*. | no `al-mcp` after the chat message; running after the command |
| L-3.7 | Start an AL debug session with the non-selected configuration. | one *Switch ALDC target* notification; *Keep* leaves the file unchanged |
| **Q-5** | Temporary agent file `.github/agents/_e010-probe.agent.md` (ignored path) with `tools:` candidates `al-mcp/al_compile`, `al-mcp/*`, `aprodaag.aproda-aldc/al-mcp/al_compile`, `aprodaAldc.alMcp/al_compile`; reload; *Configure Tools*. Delete the file afterwards. | the form(s) that list the tool as enabled |
| L-3.6 | Chat tool `startAlMcp` (`start`, `restart`). | confirmation dialog each time; result JSON; server state matches |

## Reporting format (`AlMcpE010Evidence.md`)

Per case one row: `| Case | Date | Target | Auth | AL / altool version | Route(s) | Result (counts, duration) | Deviation / note |`.
Then sections: *Q-5*, *Q-23*, *Q-24*, *OS-1 captures* (list of files), *OS-2*, *OS-3*, *pwsh stdio pass-through*
(L-2.1), *Open defects* (one line each: case, observed, expected, log excerpt without secrets).
Close with: which blocks are complete, which are blocked and why.
