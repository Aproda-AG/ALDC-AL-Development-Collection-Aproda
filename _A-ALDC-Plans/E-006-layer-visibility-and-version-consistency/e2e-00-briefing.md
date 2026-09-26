# E-006 Block 4 — End-to-end test: briefing

> **Read this file completely before starting either run.** It is the shared context for
> [`e2e-01-run-wrong-order.md`](e2e-01-run-wrong-order.md) and
> [`e2e-02-run-production-order.md`](e2e-02-run-production-order.md). Those two contain the steps;
> this one contains the facts, the rules and the reporting contract.
>
> **Single-use scaffolding.** All three files are deleted once the runs are recorded. Do not treat them
> as durable documentation.

---

## 1. What is being tested, and why

Block 4 of the E-006 remediation changed how the **BCQuality knowledge layer** is located and reached.
It was built, reviewed step by step, and committed — but **it has never been run end to end.** Every
check so far was a `-WhatIf` dry run or a scratch fixture. No real project has ever executed a real
pull, the migration, or the junction creation.

That is the gap these two runs close.

### What changed (enough to test it, not more)

| Area | Before | After |
|---|---|---|
| `aldc.yaml` location | repository root | `<toolkitRoot>/aldc.yaml` → `.github/aldc.yaml` in a project |
| BCQuality mount | the clone itself, as a sibling workspace root (`../BCQuality-Aproda`) | a tracked in-repo wrapper `.external/`, with a **junction** `.external/bcquality` pointing at the clone |
| Who finds the clone | three repo-scoped values, all wrong at once in a live project | one resolver in the VS Code extension, five rungs, every candidate probe-verified |
| How agents read it | a fallback clause that could not execute | three rungs: `#bcquality` → `#aldcConfiguration` → `read_file <toolkitRoot>/aldc.yaml` |
| `BCQUALITY_HOME` | written into the tracked `*.code-workspace` | a **Global** VS Code setting |
| Existing projects | — | migrated automatically by `Migrate-AprodaProjectLayout.ps1` (Init 5) on every pull |

### Why two runs

The junction is created by the **Aproda VS Code extension**. The layer content is delivered by the
**syncer**. They are two separate distribution channels, and they can arrive in either order.

- **Run 1** deliberately tests the **wrong order** — layer first, old extension still installed. The
  expectation is that BCQuality goes dark in the project. That expectation is currently an *assertion by
  the implementer*, not a measurement. Run 1 turns it into evidence, which then decides whether
  "extension first" is a recommendation or a hard release gate.
- **Run 2** tests the **production order** — new extension first, then the layer. This is the actual
  acceptance test.

**Run 1 is expected to produce a degraded project. That is the point.** Do not "fix" it mid-run.

---

## 2. Environment — verified 2026-09-25, do not re-derive

| Thing | Value |
|---|---|
| Fork (source of the layer) | `c:\_EphemeralWorkspace\Florian Köll\ALDC-AL-Development-Collection-Aproda` |
| Test project | `c:\_EphemeralWorkspace\Florian Köll\_GitHub\straub-medical-ag-base` |
| Test project branch | `temp/temp-testing-for-aldc` — **a throwaway branch; never switch it** |
| Workspace file in the project | `StraubMedicalAGBase.code-workspace` |
| Project layout right now | root `aldc.yaml` **present**, `.github/aldc.yaml` **absent**, `.external/` **absent** → a genuine pre-Block-4 project, not a simulation |
| Pull entry point in the project | `.github\tools\aproda-sync\Start-Pull.ps1` (machine-local, already configured) |
| BCQuality clone | `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (contains `skills\entry.md`) |
| Installed extension | `aprodaag.aproda-aldc` **0.1.7** — this is the **old** build; the repo's `package.json` also says `0.1.7`, so a rebuild alone is **not** version-distinguishable |
| Extension source | `<fork>\tools\aproda-vscode-extension`, `npm run package` → VSIX |

### The layer source — check this before anything else

The extension can apply the toolkit from two places, and **this is not visible anywhere in its output
before the fix that added it**:

| `aprodaAldc.source.mode` | What *Apply Toolkit* applies |
|---|---|
| `managed` | a cached clone of the **last released** layer version |
| `localFork` | the working tree at `aprodaAldc.source.forkPath` |

**This already invalidated one full run.** Run 2 was executed with `source.mode: "managed"`, so it
applied the *released* layer while everyone believed it was testing the local fork. Every downstream
symptom — no migration, no `.external/README.md`, no new catalog files, an untouched workspace file —
was then misread as a product defect. It was not; the fork's changes were simply never applied.

So: **verify both settings in Phase 0 and stop if they are wrong.**

```powershell
$s = "$env:APPDATA\Code\User\settings.json"
((Get-Content $s -Raw) -replace '(?m)^\s*//.*$','' | ConvertFrom-Json).PSObject.Properties |
    Where-Object { $_.Name -like 'aprodaAldc*' } | ForEach-Object { "{0} = {1}" -f $_.Name, $_.Value }
```

Required for these runs: `source.mode` = `localFork`, and `source.forkPath` pointing at the fork listed
in the table above. Anything else — **stop and report**, do not "work around" it.

**The project is backed up 1:1 by the maintainer.** Resetting it is cheap. Ask the maintainer to perform
the reset between the two runs — do not attempt to locate or restore the backup yourself.

---

## 3. Hard rules

These are not style preferences. Several of them exist because they have already gone wrong in this
project.

1. **Never `git push`.** Never switch, create or delete a branch in either repository. Never force
   anything. Committing in the test project is allowed only if a run's instructions say so.
2. **Never touch the fork's own working tree.** You are testing the project, not the toolkit.
3. **Path-based script execution is blocked** by a Software Restriction Policy. `. <path>.ps1`,
   `& <path>.ps1` and `Import-Module <path>` all throw `PSSecurityException`. The SRP-safe form is
   content-based:
   ```powershell
   & ([ScriptBlock]::Create((Get-Content <path> -Raw)))
   ```
4. **`Initialize-AprodaProject.ps1` and `Migrate-AprodaProjectLayout.ps1` anchor their `.git`-walk at
   the script's own location** (`$env:APRODA_SYNC_SCRIPTDIR` / `$PSScriptRoot`), **not** the working
   directory. Running them with the env var pointing at the fork will initialize *the fork*. This has
   already happened once. In these runs you always invoke the project's own copies under
   `<project>\.github\tools\aproda-sync\`.
5. **`.external/bcquality` is a link whose target is the real BCQuality clone, outside the repository.**
   Never `Remove-Item -Recurse` it, never `rm -rf` it, never let any script walk into it. To remove a
   junction: `(Get-Item <path> -Force).Delete()` or `cmd /c rmdir <path>`. If you are unsure, do not
   delete it — report instead.
6. **`$env:TEMP` can differ between the terminal and the tool context** on this machine
   (`C:\Users\LOCAL_~1.KOE\Temp` vs `...\florian.koell\AppData\Local\Temp`). Use absolute paths in any
   scratch work, never `$env:TEMP` in a path you later re-resolve.
7. **PowerShell 7 mangles multi-line pasted input.** For anything longer than a couple of lines, write a
   temporary `.ps1` and run it via `Get-Content <file> -Raw | Invoke-Expression`.
8. **Do not modify the implementation to make a test pass.** If something fails, that is the result.

---

## 4. How to report

Each run's instruction file lists numbered acceptance criteria (`A1`, `A2`, …). Report against those IDs.

For each criterion give: **PASS / FAIL / NOT-REACHED**, plus the *actual observed evidence* — the command
you ran and its real output, quoted briefly. "Looks correct" is not evidence. A criterion you could not
reach is `NOT-REACHED`, never an assumed PASS.

End with:

1. `## Result` — one line per criterion.
2. `## What actually happened` — a short narrative of the run, including anything surprising.
3. `## Findings` — severity (blocker / major / minor / nit), what is wrong, what it means. Include things
   that *passed but felt wrong*.
4. `## Open questions` — anything you could not decide.

---

## 5. Between runs: reset the user settings, not just the project

*Added for Runs 3 and 4. Resetting the repository is not enough — the extension writes **Global** VS Code
settings, and those survive every `git reset`. A leaked value silently short-circuits the exact rung the
next run is meant to exercise, and the run then passes for the wrong reason.*

**Clear before every run** (Settings UI → *Open User Settings (JSON)*, or the Settings editor):

| Setting | Why |
|---|---|
| `aprodaAldc.bcquality.path` | Rung 1. If set, **every** other rung becomes unreachable — the run would test nothing |
| `terminal.integrated.env.windows.BCQUALITY_HOME` | Rung 3. Written by the previous run's reconcile |
| `terminal.integrated.env.linux.BCQUALITY_HOME` | Should never exist on this host — if present, that *is* a finding (B-25) |
| `terminal.integrated.env.osx.BCQUALITY_HOME` | Same |

**Keep as-is:**

| Setting | Value | Why |
|---|---|---|
| `aprodaAldc.source.mode` | `localFork` | Otherwise the *released* layer is applied instead of the work under test — this already invalidated one full run |
| `aprodaAldc.source.forkPath` | the fork | Same |
| `aprodaAldc.devRoot` | `c:\_EphemeralWorkspace` | **Deliberately wrong** (the `Florian Köll` segment is missing). This is the misconfiguration that gave B-23 its plausible-but-wrong target; correcting it before the runs would make them prove nothing. **The maintainer fixes it after Run 4** |

Verify the state before starting:

```powershell
$s = "$env:APPDATA\Code\User\settings.json"
$j = ((Get-Content $s -Raw) -replace '(?m)^\s*//.*$','' | ConvertFrom-Json)
$j.PSObject.Properties | Where-Object { $_.Name -like 'aprodaAldc*' -or $_.Name -like 'terminal.integrated.env*' } |
    ForEach-Object { "{0} = {1}" -f $_.Name, ($_.Value | ConvertTo-Json -Compress) }
```

> **Do not edit `settings.json` with a script.** It is JSONC with comments; a `ConvertTo-Json`
> round-trip destroys them — the same defect the toolkit itself was just fixed for (B-21). Remove the
> entries by hand.

### Order

**Run 3 first, then Run 4.** Run 3 is the regression test for a shipped blocker on the known baseline;
Run 4 is new territory. If Run 4 ran first and failed, you could not tell whether the fix is wrong or
the new project is simply different.


**Do not be agreeable.** This test exists to find defects before this reaches customer repositories.
A report that confirms everything works is only useful if it is true. If a step is ambiguous, say so
rather than guessing the intent.

---

## 5. What the two runs cover

| | Run 1 (wrong order) | Run 2 (production order) |
|---|---|---|
| Extension | old `0.1.7`, untouched | new build, installed as VSIX first |
| Syncer / migration | ✅ | ✅ |
| Junction creation | ✗ (expected absent) | ✅ |
| `#bcquality` tool, status bar, status command | ✗ | ✅ |
| `BCQUALITY_HOME` as Global setting | ✗ | ✅ |
| Agent behaviour with BCQuality absent | ✅ **this is the point** | — |
| Agent behaviour with BCQuality reachable | — | ✅ |
| `enabled: false` removes the junction | — | ✅ |
| Second pull is a no-op | ✅ | ✅ |

Start with [`e2e-01-run-wrong-order.md`](e2e-01-run-wrong-order.md).
