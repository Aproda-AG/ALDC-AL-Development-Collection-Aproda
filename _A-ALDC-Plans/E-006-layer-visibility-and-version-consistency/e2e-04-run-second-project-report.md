# E2E Run 4 — Report (HEKS Base, first init)

Run against `e2e-04-run-second-project.md`, per the rules in `e2e-00-briefing.md`. No `git push`, no
branch switch, no commit was performed at any point.

## Result

| ID | Verdict | Evidence (short) |
|---|---|---|
| D1 | PASS | Clean tree pre-run; no `.github/`, `aldc.yaml`, `.external/`; no Aproda block in `.gitignore` |
| D2 | PASS | `app.code-workspace` and `.gitignore` recorded verbatim before any change; trailing comma in `search.exclude` confirmed present |
| D3 | PASS | Extension `aprodaag.aproda-aldc-0.1.8-test.4` confirmed installed; other settings preconditions held |
| D4 | PASS | Exactly one BCQuality clone on the machine at baseline (re-confirmed unchanged at D17/D26 — no second clone ever appeared) |
| D5 | PASS | Repo resolved directly to `HEKS Base` via `git status`/`git branch` probing against the fork + bootstrap target; **no quick-pick appeared** |
| D6 | PASS (duration not stopwatched) | Completed without blocking on any dialog; log timestamps show the whole bootstrap completing within seconds (05:59:32.849 → done) |
| D7 | PASS | `.github/` created with `agents/`, `docs/`, `documentation/`, `instructions/`, `plans/`, `prompts/`, `skills/`, `tools/`, `aldc.yaml`, `copilot-instructions.md`, `decisions.aproda.md`, `readme.aproda.md`, `README.md`, `site-profile.aproda.md` |
| D8 | PASS | `.github/aldc.yaml` present, non-empty, `toolkitRoot: ".github"` |
| D9 | PASS | No root `aldc.yaml`. Log explicitly states: `Init 5: [current] Root aldc.yaml already absent.` |
| D10 | PASS | `.external/` created with `README.md` |
| D11 | PASS | `.gitignore` pre-existing content preserved verbatim; Aproda `BEGIN/END` block appended containing `/.github/aldc.yaml` and `/.external/bcquality/` |
| D12 | PASS | `folders` = `.github`, `source`, `test`, `.external` (named `"BCQuality (Aproda ALDC)"`) — **`.github` was mounted too**, not just `.external` |
| D13 | PASS | `settings.cSpell.words` (`ASFI`, `HEKS`) survived unchanged |
| D14 | PASS | Pre-existing root-level `files.exclude` (`**/*.dep.app`, `**/rad.json`) survived **byte-for-byte**, not extended with BCQuality entries (those went to `settings.files.watcherExclude` instead) |
| D15 | PASS (with a structural note, see Findings) | Pre-existing root-level `search.exclude` entries survived unchanged; `bcquality/**` was added to **`settings.search.exclude`** and **`settings.files.watcherExclude`** — a separate, correctly-nested key, not merged into the sibling root-level `search.exclude` |
| D16 | PASS | `app.code-workspace.bak` is structurally identical to the D2 recording, including the trailing comma before the closing brace of the original `search.exclude` block |
| D17 | PASS | No new clone anywhere; single clone re-confirmed at end of run (D26) |
| D18 | **FAIL (finding)** | Post-bootstrap BCQuality step produced **zero log output** — the `Aproda ALDC` output log ends cleanly at `Bootstrap: done.` with no BCQuality resolver decision logged at all. Outcome is consistent (no junction, D19 holds) but the run is silent, which is exactly the shape flagged in the run instructions as suspicious |
| D19 | PASS | `.external\bcquality` did not exist yet after Apply Toolkit; `.external\README.md` intact |
| D20 | PASS | `Show BCQuality Status` listed all five rungs with per-candidate verdict, declared home (`.external/bcquality`) shown distinctly from resolved root (`none`); no false-active pretense |
| D21 | PASS | `Install / Update BCQuality` showed a modal: *"No BCQuality clone was found. Clone it to `c:\_EphemeralWorkspace\BCQuality-Aproda`?"* — the wrong-`devRoot` path, exactly as predicted |
| D22 | PASS | After Cancel: wrong-devRoot directory not created, no clone, `bcquality.path` not written, no junction |
| D23 | PASS | After setting `aprodaAldc.bcquality.path` (Global) to the real clone and re-running: **no prompt**, direct message *"BCQuality is ready at `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`."* |
| D24 | PASS | `(Get-Item '.external\bcquality' -Force).Target` = `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (asserted on `.Target`, not just existence) |
| D25 | PASS | `terminal.integrated.env.windows.BCQUALITY_HOME` set to the real clone; **no** `linux`/`osx` entries exist at all |
| D26 | PASS | Exactly one BCQuality clone on the machine after install |
| D27 | PASS | `#bcquality` `read` on `skills/entry.md` returned real content through the junction; `list` on `skills/` returned 5 entries (`do.md`, `entry.md`, `read.md`, `README.md`, `write.md`) |
| D28 | PASS | `grep_search` for a string existing only inside BCQuality content (`"consumer prunes its clone to policy"`, verbatim from `entry.md`) returned **zero hits** from this workspace |
| D29 | PASS | `#aldcConfiguration` returned the full resolved config (`toolkitRoot`, `layerVersion: "1.2.0_aproda.17"`, `bcquality.resolvedHome`, `resolvedFrom: "setting"`, `verified: true`, `mounted: true`). `read_file .github/aldc.yaml` **also** worked directly, because `.github` was mounted as a workspace folder (D12) |
| D30 | **FAIL (finding)** | `Aproda ALDC: Validate Installation` errored: `spawn npm ENOENT`. Confirmed npm **is** on PATH in a normal terminal (`11.19.0`, `C:\Program Files\nodejs\npm.cmd`) — this points to a genuine implementation bug (classic Windows `child_process.spawn('npm', …)` needing `shell: true`/`.cmd` resolution), not a missing dependency |

## What actually happened

Phase 0 confirmed a genuinely untouched repository: no `.github/`, no `aldc.yaml` anywhere, no
`.external/`, and the deliberately-wrong `devRoot` setting still in place. `app.code-workspace` and
`.gitignore` were recorded verbatim, including the non-standard structure of the workspace file (its
`files.exclude`/`search.exclude` sit at the JSON root, outside `"settings"`, and the file has a trailing
comma — neither of which is valid strict JSON).

**Apply Toolkit to Project (per Repo)** ran cleanly and resolved the repository correctly even though the
repository root is not itself a workspace folder — it worked entirely off `git status`/`git branch`
probing against the fork and the bootstrap target, with no quick-pick needed. It ran two pull passes (an
initial one, then a "settle" pass once the freshly-written `aldc.yaml` made the framework resolvable),
copied 135 layer files plus the `aldc.yaml` dual-variant, added the `.gitignore` block, rewrote
`app.code-workspace` (mounting **both** `.github` and `.external`, not just `.external`), and created
`.external/README.md`. Init 5 (the migration/legacy-layout check) explicitly logged that the project
layout was already current and that no root `aldc.yaml` or legacy sibling BCQuality root was found —
confirming a genuine first-init landing directly on the target shape.

The one thing the Apply Toolkit log does **not** show is any trace of the post-bootstrap BCQuality
resolution step: the log simply ends at `Bootstrap: done.`. File-system evidence (no junction, `.external`
otherwise intact) shows the *outcome* was correct — but there is no observable proof the decision logic
actually ran, as opposed to silently not being invoked. This is the exact "silence" shape the run
instructions call out as indistinguishable from the previously-broken first-repair behavior.

`Show BCQuality Status` correctly reported all five resolver rungs, none resolved, without pretending
otherwise. Triggering `Install / Update BCQuality` with the still-wrong `devRoot` in place produced the
expected confirmation modal naming the wrong path; cancelling it left no trace. Setting
`aprodaAldc.bcquality.path` to the real clone and re-running produced a silent, correct update: the
junction was created pointing at the real clone, `BCQUALITY_HOME` was set as a **Global**,
Windows-only setting, and the machine still has exactly one clone.

The knowledge layer itself worked end-to-end: `#bcquality` could read and list through the junction,
the workspace-wide search exclusion held (no leakage of BCQuality-only content into `grep_search`), and
`#aldcConfiguration` resolved the full configuration correctly — including confirming that `.github` was
mounted as a workspace folder, so direct `read_file` access to `.github/aldc.yaml` also works here, unlike
a project where `.github` is not mounted.

The one clearly broken step was `Validate Installation`, which failed immediately with `spawn npm
ENOENT` despite npm being present and functional in a normal terminal session — an implementation bug
unrelated to the BCQuality/junction work this run exists to test.

Mid-session, VS Code showed an unplanned **"Please confirm restart of extensions" / "A session is in
progress"** modal; the user chose "Restart Anyway" and VS Code fully restarted. File-system state was
verified unchanged before and after (same git status, no new junction, no new clone), and the Phase 1
evidence that had been read from the live output channel before the restart was recovered from the
persisted log file on disk (`...\output_logging_20260926T075618\8-Aproda ALDC.log`), so no evidence was
lost — but it did interrupt live observation of the process.

No reset, commit, or push was performed. Final `git status --short`:

```
 M .gitignore
 M app.code-workspace
?? .external/
?? .github/
?? source/e2e-00-briefing.md
?? source/e2e-04-run-second-project.md
```

## Findings

- **Major — D18, silent post-bootstrap BCQuality step.** The Apply Toolkit log ends at `Bootstrap:
  done.` with no logged BCQuality resolution attempt at all — no "no verified root" message, no
  decision, nothing. The end state is correct (no junction, since nothing could resolve), but the
  process gives no observable evidence it evaluated the five rungs at first-init time, as opposed to
  simply not running. The run instructions flag exactly this shape as equivalent to the previously
  broken first-repair path. Recommend adding an explicit log line for this step even (especially) when
  it concludes "no verified root, therefore no junction."
- **Major — D30, `Validate Installation` fails with `spawn npm ENOENT`.** npm is present and working
  in a normal terminal (`11.19.0`). This is very likely the classic Windows Node.js bug where
  `child_process.spawn('npm', …)` needs `shell: true` (or must resolve `npm.cmd` explicitly) to find the
  `.cmd` shim; without it, Node reports `ENOENT` even though the executable is on `PATH`. This command
  is unusable on this machine as shipped.
- **Minor — pre-existing workspace-file structure, not a toolkit defect.** `app.code-workspace` (both
  before and after the rewrite) carries `files.exclude` and `search.exclude` at the **JSON root**,
  sibling to `"settings"`, rather than nested inside it. VS Code only honors these keys under
  `"settings"`, so the pre-existing customizations were arguably already inert before this run started.
  The toolkit correctly added its own `bcquality/**` entries to the properly-nested
  `settings.search.exclude` / `settings.files.watcherExclude`, but did not merge with (or flag) the
  sibling root-level block. Worth a note to project maintainers, not a toolkit bug.
- **Minor — procedural, unplanned mid-run extension restart.** A "Please confirm restart of
  extensions" / "A session is in progress" dialog appeared mid-run for reasons not diagnosed (possibly
  triggered by a Settings UI interaction). It did not corrupt any file-system state and evidence for
  the interrupted phase was fully recoverable from persisted VS Code logs, but it interrupted live
  observation and should be noted as a source of run fragility if it recurs.
- **Nit — D6 duration not stopwatched.** No literal stopwatch was run; duration was inferred from log
  timestamps only (well under 10 seconds visible). Acceptable given the log evidence, but not a
  precise measurement as the criterion technically asks for.

## Open questions

1. Is the D18 silence intentional (the resolver step genuinely has no "nothing to do" log line by
   design) or a gap that should be closed with an explicit log entry? The run instructions treat this
   ambiguity itself as the finding, so this needs a maintainer decision rather than a guess from this
   run.
2. Is `Validate Installation`'s `spawn npm ENOENT` a known/tracked issue, or new? It blocked D30 outright
   and could not be worked around within the rules of this run (no modifying the implementation).
3. Should the toolkit's workspace-file rewrite detect and either warn about or migrate the pre-existing
   root-level `files.exclude`/`search.exclude` keys into `settings`, given they appear to already be
   inert in this project regardless of the toolkit's own changes?
4. What actually caused the mid-run "restart of extensions" prompt? It was not deliberately triggered by
   any step in this run's instructions.

## Answers to the four required questions

1. **Did a first init land directly on the T-33 shape, with no root `aldc.yaml`?** Yes — confirmed both
   by file-system state (D9) and by the Apply Toolkit log's explicit `Init 5: Root aldc.yaml already
   absent.` line.
2. **Did the post-bootstrap BCQuality step run, and what did it decide?** Unknown from the log — it
   produced no output at all. The resulting file state (no junction) is consistent with "correctly
   decided nothing was resolvable," but there is no direct evidence it ran versus was skipped; see the
   D18 finding.
3. **Did any step create a second clone?** No — verified before (D4), immediately after Apply Toolkit
   (D17), and after the successful install (D26): exactly one clone on the machine throughout.
4. **What exactly does the junction point at?** `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`
   — the real clone, confirmed via `(Get-Item '.external\bcquality' -Force).Target`, not merely its
   existence.
