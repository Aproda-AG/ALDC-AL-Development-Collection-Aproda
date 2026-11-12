# E-010 — Live test brief 2 (retest of the open points)

**Date:** 2026-11-12. **For:** the Copilot session in *Gustav Gerig AG Base* (TOGA and Fkh dev2).
**Scope:** only what the first run left open or found broken (evidence of run 1:
[`live-evidence/AlMcpE010Evidence.md`](live-evidence/AlMcpE010Evidence.md)). Cases that passed in run 1 are not
repeated. Case IDs `R-<original ID>`; expected results here override the test plan where they differ.
**Fixed in the fork since run 1:**

| Defect | Fix | Where |
|---|---|---|
| D-4 | `GetPackageManifest` path is positional → dependency preflight and MS test-library auto-install run again | DRV engine |
| D-5 | publish without an HTTP answer = `InvocationFailure`, locale independent (German socket texts) | DRV engine |
| D-10 | `runtests` 401 = `AuthFailure` (one re-prompt, no web-client fallback) | DRV engine |
| L-4b.11 | after `PUBLISH_REJECTED` the engine prints `STATE AFTER REJECT:` and warns when no version is left installed | DRV engine |
| L-4b.9 (b) | a re-prompted credential is saved after the first non-401 HTTP answer (also on 422) | DRV engine |
| L-H.4 note | provider-qualified paths (`Microsoft.PowerShell.Core\FileSystem::`) are normalized | DRV engine |
| D-6 / Q-23 | server id derived from the extension id: `aprodaag.aproda-aldc/al-mcp` | extension `0.2.1` |
| D-7 | the server restarts by itself after a definition change (target switch, `launch.json`, credential) | extension `0.2.1` |
| D-8 | credential terminal closes after a successful save; on failure the message stays until Enter | extension `0.2.1` |

**Not in scope:** D-9 (`al-developer` tools) — that is phase 4c and is tested with `L-4c.*` afterwards.
**Report to:** append a section `## Run 2 (brief 2)` to `.github/documentation/ALDC/AlMcpE010Evidence.md` (English,
same row format as run 1).

## Safety rules (binding, unchanged from brief 1)

1. Targets: only `TOGA_FOOD_SA_28_AG_28_CH_FKO` (ASINST, `Windows`) and
   `flobi-wan-kenobi-gustavgerig-dev2-deployment` (Fkh, `UserPassword`).
2. Environment acknowledgement by Florian once at the start of each block that writes to a target. `ForceSync` for the
   regular Base/Test publishes as approved in run 1, unless Florian says otherwise.
3. Removals and `forceUpgrade`: only the disposable app `E010 Recovery Probe`, each after its own confirmation.
   Never remove Base `25.0.0.156`.
4. No password, header, token or credential value in any output, file, capture or report. Wrong test passwords
   are **ASCII only** (a non-ASCII one ends in `CREDENTIAL_NON_ASCII`, not in an auth failure).
5. Do not commit anything in the project. Temporary files under `Test/PowerShell/_temp/`. The real
   `Test/deploy-run-verify.config.jsonc` stays untouched; use scratch copies as in run 1.
6. A failed case: stop the block, report, wait. No edits to `.github/skills/**` or other layer files.
7. The DRV preflight may install missing Microsoft test libraries (D-52 addendum) — a target write, only inside an
   acknowledged block; record every `AUTO-INSTALL (MS test library)` line.

## Block 0 — Preparation (Florian, agent checks)

| Step | Action | Check |
|---|---|---|
| 0.1 | Fork: commit the fixes; record the fork HEAD. | `git status` of the fork clean except unrelated files |
| 0.2 | Project: *Aproda ALDC: Apply Toolkit to Project (per Repo)* (`localFork` stays set). This overwrites the local D-5 patch in the project engine — expected, the fork now has it. | Engine `.psm1` hash = fork; it contains `Get-DeployRunVerifyStateAfterReject` and `GetPackageManifest', $AppFile` (positional form) |
| 0.3 | Install `tools/aproda-vscode-extension/dist/aproda-aldc-0.2.1.vsix` from the fork (*Extensions: Install from VSIX*), then *Developer: Reload Window*. This also removes the locally patched `serverCommands.js` of 0.2.0. | Installed version `0.2.1`; `…\aprodaag.aproda-aldc-0.2.1\dist\alMcp\serverCommands.js` contains `toLowerCase` and no `aprodaAldc.alMcp/al-mcp` |
| 0.4 | No interim `al-mcp` registration left: `.github/.vscode/mcp.json` absent; the prototype entry in `Base/.vscode/mcp.json` disabled (as in run 1). | *Aproda ALDC: Environment Diagnostics* shows no duplicate-registration warning |
| 0.5 | Record VS Code version, `chat.mcp.autostart`, harness (*Local*), fork HEAD, selection (`.github/aldc.local.json`). | values in the report header |
| 0.6 | Read-only: `Get-DeployRunVerifyCleanupCandidates` against TOGA with a scratch config that lists Base, Test and the probe. Run 1 contradicts itself on whether probe `1.0.0.3` is still there. | listing recorded; nothing removed |

## Block E — Extension `0.2.1` (Local harness; Florian does the UI steps, the agent records)

Keep the *Aproda ALDC* output channel open; the extension now logs `workbench.mcp.startServer issued for '…'` and
`AL MCP definition version changed …; restarting al-mcp.`

| Case | Steps | Expected |
|---|---|---|
| R-3.8 | `aprodaAldc.alMcp.start = auto` (default). *Developer: Reload Window*, do not open chat. | `al-mcp` *Running* in *MCP: List Servers* before the first chat message; log line `workbench.mcp.startServer issued for 'aprodaag.aproda-aldc/al-mcp'` |
| R-3.1 | *Select AL Target*: TOGA → Fkh → TOGA, wait ~5 s after each switch. | file rewritten each time; after each switch `al-mcp` is *Running* again **without** a manual restart; one *restarting* log line per switch; no trust dialog (Q-24 stays) |
| R-3.2 | After the last switch: `al_run_tests` 59021 with the bundle from `#aldcConfiguration` (+ `environmentType: OnPrem`, `company`), on the selected target; switch once more and repeat on the other target. | complete run on both targets |
| R-3.3 | Rename the stored Fkh credential file (agent, on request), *Restart AL MCP Server* → notification → *Store credential* → enter the password. | terminal **closes by itself** after the save; `al-mcp` restarts by itself; `al_run_tests` 59021 on Fkh complete; renamed leftover deleted |
| R-3.3b | Same flow, but cancel the `Get-Credential` prompt. | terminal stays open with `Credential NOT stored: …` until Enter; no password shown; then restore the credential (store it again) |
| R-3.7 | AL debug session with the non-selected configuration → *Switch*. | selection switched; `al-mcp` restarts by itself (run 1: it stayed stopped) |
| R-3.9 | `aprodaAldc.alMcp.start = manual`, reload, send a chat message; then *Aproda ALDC: Start AL MCP Server*; then *Select AL Target* once. | no `al-mcp` after the chat message; *Running* after the command; after the target switch it restarts by itself (start was requested in this window). Set the mode back to `auto` afterwards |
| R-3.6 | Chat tool `startAlMcp` `restart` (default permissions). | confirmation dialog; result `restarted`; log line with the derived id |

## Block D — DRV engine (Local harness) · writes to both targets

Acknowledgement by Florian before the block. Scratch configs as in run 1 (`Test/PowerShell/_temp/e010-cfg-*.jsonc`).
Set `$env:APRODA_DEPLOY_RUN_VERIFY_*` per run and remove them afterwards. Keep each engine log under
`Test/PowerShell/_temp/logs/R-*.log`.

| Case | Target | Steps | Expected |
|---|---|---|---|
| R-4b.13 | Fkh, then TOGA | `full` per target | **no** `GetPackageManifest failed` / *preflight … skipped* warning (D-4); the preflight runs; record `AUTO-INSTALL (MS test library)` lines (normally none); routes `altool`; run complete |
| R-4b.8 | — | scratch configuration with the wrong port (as in run 1, restore byte-for-byte), `skipbuild` | altool `InvocationFailure` → direct POST `InvocationFailure` → `PUBLISH_FAILED … route devEndpoint could not reach the target`; no target change (this time with the fork engine, not the project patch) |
| R-4b.9a | Fkh | Florian stores an **ASCII** wrong password; `full` (fresh build, so no duplicate) | altool `InvocationFailure` → direct POST 401 → *Authentication … was refused* → exactly one re-prompt → right password → published, state verified; store updated (`Fkh-Credential-Store aktualisiert`) |
| R-4b.9b | Fkh | wrong password stored again; `runonly` | `runtests` 401 → **`AuthFailure`** (no `ROUTE-FALLBACK: tests → webClient`) → one re-prompt → right password → complete; store updated |
| R-4b.9c | Fkh | wrong password stored; `full`; at the re-prompt enter a wrong password again | `PUBLISH_AUTH_FAILED`, stop, no other route |
| R-4b.9d | Fkh | wrong password stored; `runonly`; wrong again at the re-prompt | `TESTS_AUTH_FAILED`, stop |
| — | Fkh | restore the right credential (Florian) and confirm with one `runonly` | complete |
| R-4b.11 | TOGA | probe app (`Test/PowerShell/_temp/e010-probe`): publish a clean version (`Add`), then a version with a removed field with `Add` | 2nd publish `PUBLISH_REJECTED` followed by `STATE AFTER REJECT: E010 Recovery Probe installed=…; published=…`; if nothing is installed, the message ends with *Target left without an installed version* (run 1 observed this) — record which |
| R-4b.10 | TOGA | rebuild the probe (new package ID), `ForceSync` scratch config | `SCHEMA MODE: ForceSync (fkhSyncMode)`, publish green, probe installed and `Synced` |
| R-4b.11b | TOGA | cleanup listing; remove the probe completely after Florian's confirmation (Q-16 sequence) | no probe left; Base/Test installed versions unchanged; Base `25.0.0.156` untouched |
| R-H.4u | Fkh | from a pwsh whose working directory is the UNC path of the project (`\\APD-AZU-FS01\…\Gustav Gerig AG Base`), load the entry SRP-safe and run `buildonly` with a config path derived by `Resolve-Path` (the run-1 failure) | `Build OK`; no `Microsoft.PowerShell.Core\FileSystem::` in the `altool compile` arguments |

## Reporting

Append `## Run 2 (brief 2)` to the evidence file: environment table, one row per `R-*` case in the run-1 row format,
then *Open defects (run 2)* — one line each: case, observed, expected, log excerpt without secrets. Close with which
cases passed, failed, or were not run, and why. Do not overwrite the run-1 content.

## After the run (Florian)

- `aprodaAldc.alMcp.start` back to `auto`; selection back to the usual target.
- Scratch changes reverted (`launch.json`, configs); `_temp` may stay (git-ignored).
- Hand back: the evidence file, new logs only if asked.
