# E-011 — Live test brief (phase 4)

**For:** the Copilot session in *Gustav Gerig AG Base* (`I:` = network share, junction from E-010 broken), plus
one project on a local drive for the junction case. **Source of truth:** [`E-011.test-plan.md`](E-011.test-plan.md)
§4 (cases `L-11.*`), [`E-011.spec.md`](E-011.spec.md), decision D-54. No BC target needed.
**Report to:** `Gustav Gerig AG Base/.github/documentation/ALDC/E011Evidence.md` (new file, English; one row per
case: `| Case | Date | Project / drive | Mount | Result | Evidence (log lines, git diff, tool output) | Note |`).

## Safety rules

1. Do not commit or push anything in the project. The migrated workspace file is committed by Florian at the end —
   and **pushed only after `0.3.0` is rolled out**, otherwise colleagues on older versions see an unavailable
   `.external` root.
2. Back up the project's `*.code-workspace` before block 0.3 (`Test/PowerShell/_temp/e011-workspace-before.json`)
   and record its SHA-256.
3. Never delete through a link: the junction is removed only as a link (`cmd /c rmdir`), never with `Remove-Item -Recurse`.
4. Settings changes (`aprodaAldc.external.mount`, `aprodaAldc.bcquality.path`) are made by Florian in the user
   settings; the agent records them. Restore them at the end.
5. A failed case: stop, report, wait. No edits to the extension or layer files.

## Block 0 — Preparation

| Step | Who | Action | Check |
|---|---|---|---|
| 0.1 | Florian | Fork HEAD `ff81222` or later on `feature/e006-bcquality`; record it. | `git status` of the fork clean except unrelated files |
| 0.2 | agent | Backup + hash of the workspace file (rule 2); `dir /a .external` (junction state); `git status --short`. Before 0.3: Apply can already touch the workspace file (run-1 O-3). | values recorded |
| 0.3 | Florian | Project: *Aproda ALDC: Apply Toolkit to Project (per Repo)* (`localFork`). | `.github/copilot-instructions.md` contains *Reaching BCQuality — access rule*; `.external/README.md` mentions `aldc-external:/` |
| 0.4 | Florian | Install `tools/aproda-vscode-extension/dist/aproda-aldc-0.3.0.vsix` from the fork, then *Developer: Reload Window*. | installed version `0.3.0` |
| 0.5 | agent | Record VS Code version, `aprodaAldc.external.mount` (default `virtual`), `aprodaAldc.bcquality.autoReconcile`, `aprodaAldc.bcquality.path`, harness. | report header |

## Block A — Migration and Explorer (Local harness)

| Case | Steps | Expected |
|---|---|---|
| L-11.1 | After the reload in 0.4: read the *Aproda ALDC* output channel; `git diff` of the workspace file; `dir /a .external`. | Log shows the migration (`.external` path root → `uri`); `git diff` changes only that entry (comments kept); junction removed **or** the warning with `cmd /c rmdir "…\.external\bcquality"` (network share). Explorer: `.external` → `README.md`, `bcquality/…` |
| L-11.2 | Open `bcquality/skills/entry.md` from the Explorer; try to edit and save; right-click → *Reveal in File Explorer (real path)*; palette *Aproda ALDC: Reveal BCQuality Clone*. | Content shown; save refused (read-only); Windows Explorer opens the clone (`C:\…\BCQuality-Aproda`) both times |
| L-11.6 | Florian sets `aprodaAldc.external.mount = none` (no reload), then back to `virtual`. | `.external` shows `README.md` only, then `bcquality/` again; `git diff` of the workspace file unchanged by the switch |
| L-11.8 | Florian sets `aprodaAldc.bcquality.path` to an existing folder without `skills/entry.md`; reload; restore the setting. | One warning naming the path, its verdict and the clone actually used; no second warning after another reload with the same value |

## Block B — Agent access (both harnesses)

| Case | Steps | Expected |
|---|---|---|
| L-11.3 | **Local** harness: `#bcquality` `read skills/entry.md`; then `read_file aldc-external:/bcquality/skills/entry.md`; `#aldcConfiguration`. | Both reads succeed; `bcquality.mount = virtual`, `mountUri = aldc-external:/bcquality/`, no `diskPath` |
| L-11.4 (M-1) | New **Copilot** harness session: same three calls. | Record which succeed. `#bcquality` must work; the URI read may fail (path-based tools) — that is the measurement |
| L-11.5 (M-3) | `al_symbolsearch "Event Audit Buffer"`; Problems panel; workspace search for `avoid-growing-globals`. | No hit and no diagnostic from `aldc-external:` |

## Block C — No overwrites between developers, legacy layout

| Case | Steps | Expected |
|---|---|---|
| L-11.9 | Florian sets `aprodaAldc.external.mount = junction`; reload; then `virtual` again; reload. | Workspace file byte-identical to the state after L-11.1 both times (only the junction attempt differs — on `I:` it fails with the network-drive warning) |
| L-11.11 | Agent replaces the `.external` entry in the workspace file by a legacy entry `{ "name": "BCQuality", "path": "../../BCQuality-Aproda" }` plus a comment line above it, adds `"BCQUALITY_HOME": "x"` under `settings."terminal.integrated.env.windows"`; reload. | Legacy entry replaced by the constant entry, `BCQUALITY_HOME` removed (empty container removed), the comment line kept; file equal to the L-11.1 state except for that comment |

## Block D — Local drive, junction mode

| Case | Steps | Expected |
|---|---|---|
| L-11.7 | A project on a local drive (Florian picks one; same preparation 0.2–0.4): mount `junction`, reload. | `.external/bcquality` junction created and readable; `#aldcConfiguration` shows `diskPath`; Explorer still shows the virtual `bcquality/`; the workspace file has the constant entry (migrated if needed) |
| — | Mount back to `virtual`, reload. | Junction removed (link only; clone intact) |

## Closing

| Case | Steps | Expected |
|---|---|---|
| L-11.10 | `git status --short` in both projects. | Only the one-time workspace migration (and the `.external/README.md` from 0.2). Settings restored (rule 4). |

Report: environment table, one row per case, *Open defects* (case, observed, expected, log excerpt), and which
cases passed, failed or were not run and why.

## Retest after run 1 (`0.3.1`)

Run 1 ([evidence](evidence/E011Evidence-run1.md)) found D-1…D-5. Fork HEAD `40aedaf` or later; same safety rules.
**Report to:** `E011Evidence-run2.md` next to the run-1 file in the project, same row format.

| Step | Who | Action | Expected |
|---|---|---|---|
| R.0 | agent | `git status --short`, hash of the current workspace file and of `.external/README.md`. | values recorded |
| R.1 (D-1) | Florian | *Apply Toolkit to Project (per Repo)* (`localFork`). | `.external/README.md` replaced by the current seed (log: *refreshed*) unless it was edited locally (then: kept + hint) |
| R.2 | Florian | Install `dist/aproda-aldc-0.3.1.vsix`; *Developer: Reload Window*. | installed version `0.3.1` |
| R.3 (L-11.1, D-2) | agent + Florian | Agent restores the pre-migration workspace file from `Test/PowerShell/_temp/e011-workspace-before.json`; Florian reloads **once**. | Migration logged; either the `.external` root switches on its own, or within a few seconds *Reload Window* is offered and, after it, the root shows `README.md`, `bcquality/…`. No second manual reload needed |
| R.4 (L-11.11, D-5) | agent | As L-11.11 (legacy entry with a comment line above, `BCQUALITY_HOME`); reload. | Comment line kept, entry replaced at the same position; `BCQUALITY_HOME` and the empty container removed |
| R.5 (L-11.2, D-3) | Florian | Select `bcquality/skills/entry.md` in the Explorer, then right-click another file → *Reveal in File Explorer (real path)*; then palette *Reveal BCQuality Clone* with an Explorer node selected. | Windows Explorer opens with the clicked file selected (not the selection), then with `skills/entry.md` in the clone |
| R.6 (L-11.8, D-4) | Florian | `aprodaAldc.bcquality.path` = existing folder without `skills/entry.md`; reload; reload again; restore. | Exactly one warning over both reloads; no *Install BCQuality* prompt |
| R.7 (L-11.10) | agent | `git status --short`. | Only the workspace migration and `.external/README.md` |
