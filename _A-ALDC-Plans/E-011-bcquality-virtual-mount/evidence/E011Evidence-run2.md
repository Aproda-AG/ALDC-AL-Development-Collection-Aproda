# E-011 — Live test evidence, retest run 2 (`0.3.1`)

**Status:** FINAL (2026-11-13, 20:05 CET). Junction cases (L-11.7, L-11.9) not tested by decision of Florian.
**Brief:** `_e2e-tests/e-011/E-011-live-test-brief.md`, section *Retest after run 1 (0.3.1)*; **run 1:** [`E011Evidence-run1.md`](E011Evidence-run1.md) (defects D-1…D-5).
**Rules observed:** no commit, no push; no edits to extension or layer files; temporary files only under
`Test/PowerShell/_temp/` (git-ignored); the workspace file was changed by the agent only through the restores in
R.3 and the L-11.11 fixture in R.4; end state = L-11.1 state (`E8D1896E…`). Settings changes made by Florian
and restored (rule 4).

## Environment

| Item | Value |
|---|---|
| Date | 2026-11-13 |
| Project / drive | Gustav Gerig AG Base, `I:\Florian Köll\Gustav Gerig AG Base` (network share) |
| VS Code | 1.144.0 (`2c33b50b16c472efe58357d1d2a8a5414bc23fbf`) |
| Extension | `aprodaag.aproda-aldc@0.3.1` (`code --list-extensions --show-versions`) |
| Layer apply | local fork `C:\_EphemeralWorkspace\Florian Köll\ALDC-AL-Development-Collection-Aproda`, branch `feature/e006-bcquality` |
| `aprodaAldc.external.mount` / `bcquality.autoReconcile` | unset → defaults (`virtual` / on) |
| `aprodaAldc.bcquality.path` | `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (restored after R.6) |
| BCQuality clone | `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`, HEAD `d97329b`, clean before and after |
| Harness | Local (VS Code chat) |
| Log used | *Aproda ALDC* output channel files under `%APPDATA%\Code\logs\20261113T082132\window10\exthost\output_logging_*` (log timestamps are UTC; local = UTC+1) |

### Snapshots (`Test/PowerShell/_temp/`)

| Snapshot | File | SHA-256 (first 8) |
|---|---|---|
| Pre-migration workspace file (= `HEAD`) | `e011-workspace-restored.json` | `BF783F13` |
| After migration (L-11.1 state) | `e011-workspace-after-L111.json`, `e011-run2-workspace-before-R3.json` | `E8D1896E` |
| L-11.11 fixture v2 (comment line above the legacy entry) | `e011-workspace-L1111-legacy-v2.json` | `335A2E11` |
| R.4 result (L-11.1 state + comment line) | `e011-run2-R4-result.json` | `020377C5` |

## Results

| Case | Date | Project / drive | Mount | Result | Evidence (log lines, git diff, tool output) | Note |
|---|---|---|---|---|---|---|
| R.0 | 2026-11-13 | Gustav, `I:` | virtual | done | Baseline taken from the brief; verified at start: workspace file `E8D1896E…`; `git status --short`: ` M .external/README.md`, ` M .gitignore`, ` M Base/.vscode/launch.json`, ` D Base/.vscode/mcp.json`, ` M Base/app.json`, ` M GustavGerigAG.code-workspace`, `?? .github/_e2e-tests/`, `?? .github/documentation/ALDC/` | `.external/README.md` was already ` M` at that point (R.2 done by Florian) |
| R.1 | 2026-11-13 | Gustav, `I:` | — | done (Florian) | `code --list-extensions --show-versions` → `aprodaag.aproda-aldc@0.3.1` | |
| R.2 (D-1) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | Log (18:28Z): `Init: .external/README.md refreshed from the current template (previous version was an unmodified seed).`, `Init: GustavGerigAG.code-workspace already has the required roots and settings — skipped.`, `Init 5: project layout already current -- nothing to migrate.` README normalised SHA-256 `5E44D041F9B0A671B521D12A07D6FF6B698717D9C822F5D5DEA974B39A68186C` = the seed `tools/aproda-sync/templates/external-readme.seed.md` (old `fbe112c3…` replaced); line 11 mentions `aldc-external:/`, line 13 says *"The root is editable"*. Workspace file stays `E8D1896E…` | |
| R.3 (L-11.1, D-2) — first attempt | 2026-11-13 | Gustav, `I:` | virtual | **inconclusive** | File restored to `BF783F13…` at 19:38; Florian reloaded at 19:40:24. Log of that window: only `Aproda ALDC extension activated.` (18:40:25Z) and the MCP lines — **no migration line**, and the window lived until 19:44. See O-1 | The toast Florian saw first belongs to the R.4 reload (19:44), not to this one |
| R.3 (L-11.1, D-2) — repeat | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | File restored to `BF783F13…` at 19:47:49, one reload by Florian. Log:<br>`[18:49:23.701Z] Aproda ALDC extension activated.`<br>`[18:49:32.990Z] Workspace migration (GustavGerigAG.code-workspace): replaced .external path root by aldc-external:/`<br>`[18:49:35.996Z] WARNING: Workspace migration written, but VS Code still shows the previous root; offering a reload.`<br>Toast *"ALDC updated the workspace file, but VS Code has not applied it yet. Reload the window to show the new .external root."* with *Reload Window* shown (screenshot); after clicking it the root shows `README.md`, `bcquality/…`, `SSC Bartender Beispiel setup`. File hash after = `E8D1896E…` (mtime 19:49:32.936) | Toast 3 s after the write; the one reload via the toast is the intended path, no manual second reload needed |
| R.4 (L-11.11, D-5) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | Fixture v2 (`335A2E11…`: comment line above the legacy entry `../../BCQuality-Aproda`, `BCQUALITY_HOME` under `terminal.integrated.env.windows`), reload 19:44:17. Log:<br>`[18:44:33.771Z] Workspace migration (GustavGerigAG.code-workspace): replaced legacy BCQuality root '../../BCQuality-Aproda' by aldc-external:/`<br>`[18:44:33.771Z] Workspace migration (GustavGerigAG.code-workspace): removed BCQUALITY_HOME from terminal.integrated.env.windows`<br>`[18:44:36.779Z] WARNING: … offering a reload.`<br>`git diff --no-index e011-workspace-after-L111.json → result`: exactly one added line, `+    // E-011 L-11.11: legacy BCQuality root (clone mounted directly)`, directly above `{ "name": ".external", "uri": "aldc-external:/" }`; no `BCQUALITY_HOME`, no empty container left. Result hash `020377C5…` | Comment kept, entry replaced at the same position (D-5 fixed). The fixture was written by the agent between the 19:40 and 19:44 reloads |
| R.5 (L-11.2, D-3) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | Florian: with `bcquality/skills/entry.md` selected, *Reveal in File Explorer (real path)* on another file → that file revealed and selected; *Reveal BCQuality Clone* with an Explorer node selected → Windows Explorer shows `skills/entry.md` in the clone | |
| R.5a (writable root) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | Florian: create / edit / save / rename / delete `.external/e011-write.md` all work; append blank line to `bcquality/skills/entry.md`, save, undo, save works; deleting `bcquality` refused. Disk check by the agent afterwards: `git -C <clone> status --short` empty (HEAD `d97329b`), `entry.md` hash `44590D0A` as before the test, `.external/` holds `README.md` and `SSC Bartender Beispiel setup` only (no `e011-write.md`), workspace file `E8D1896E…` | |
| R.6 (L-11.8, D-4) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | `aprodaAldc.bcquality.path` = `I:\Florian Köll\Gustav Gerig AG Base\Test\PowerShell\_temp` (exists, no `skills/entry.md`). On saving the setting, one toast (screenshot) and one log line:<br>`[18:57:58.912Z] WARNING: aprodaAldc.bcquality.path points to I:\Florian Köll\Gustav Gerig AG Base\Test\PowerShell\_temp (noEntryPoint); BCQuality is served from c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda (devRoot).`<br>Reload 1 (`18:58:21Z` activation) and reload 2 (`18:59:50Z` activation, window11): no log line, no notification, no *Install / Update BCQuality* prompt (Florian). Setting restored to `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (checked in user `settings.json`) | Exactly one warning over both reloads |
| R.7 (L-11.10) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | `git status --short` at the end: identical to R.0 — ` M .external/README.md`, ` M .gitignore`, ` M Base/.vscode/launch.json`, ` D Base/.vscode/mcp.json`, ` M Base/app.json`, ` M GustavGerigAG.code-workspace`, `?? .github/_e2e-tests/`, `?? .github/documentation/ALDC/`. `git diff --stat -- GustavGerigAG.code-workspace`: 1 insertion, 1 deletion (the one-time migration `"path": ".external"` → `"uri": "aldc-external:/"`). Workspace file `E8D1896E…`; `.external/README.md` = current seed; clone clean; user settings equal to the baseline | New vs. the pre-test list: nothing |
| L-11.7, L-11.9 | — | — | — | **not tested** | — | Junction cases excluded by Florian (2026-11-13) |

## Defect status

| # | Case | Run 1 | Run 2 |
|---|---|---|---|
| D-1 | README not refreshed by *Apply Toolkit* | open | **fixed** (R.2) |
| D-2 | Old root stays until a second manual reload, no prompt | open | **fixed** (R.3, R.4): migration write is followed by a *Reload Window* offer after 3 s; the toast's reload shows the virtual root |
| D-3 | Reveal does nothing with an Explorer selection | open | **fixed** (R.5) |
| D-4 | Two notifications per reload, repeated on every reload | open | **fixed** (R.6) |
| D-5 | Comment line removed with the legacy entry | open | **fixed** (R.4) |

No new defects.

## Observations (no defect)

- O-1 (R.3, first attempt): after the restore to `BF783F13…` the reload at 19:40:24 produced no migration line and no
  toast, although the next attempt (19:49) migrated within 9 s. The agent has no record of the file state between
  19:38 and 19:43; the only file write seen in that interval is the agent's fixture write for R.4 (~19:43:39, git
  refresh in the GitLens/Git Graph logs). Not reproducible; worth a re-run if it shows up again. Possible factor: the
  reload happened shortly after the previous window's restore, with the extension not yet reconciling.
- O-2: The R.4 reload ran before the clean R.3 measurement; the order in this report follows the brief, the order in
  time was R.3 (inconclusive) → R.4 → R.3 (repeat).
- O-3 (R.5a): `bcquality` is refused for deletion, files inside the clone and in `.external/` are written through to
  disk (spec §2.3, writable root).

## Summary

| Result | Cases |
|---|---|
| **Passed** | R.0, R.1, R.2, R.3 (repeat), R.4, R.5, R.5a, R.6, R.7 |
| **Inconclusive** | R.3 first attempt (O-1) |
| **Not tested** | L-11.7, L-11.9 (junction) |
| **Failed** | none |

**Before committing the workspace migration:** the committed file will be the L-11.1 state (`E8D1896E…`); push only
after `0.3.1` is rolled out (brief, safety rule 1).
