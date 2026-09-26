# Run 3 — regression test for the run-2 blockers (B-23 … B-26)

> **Read [`e2e-00-briefing.md`](e2e-00-briefing.md) first** — environment facts, hard rules, and §5
> (the user-settings reset). This file only adds what is specific to Run 3.

**Purpose.** Run 2 scored 26/30 and found four defects. All four are fixed and committed
(`517cd74`, `83a4227`). This run proves the fixes on the same project, under the **same conditions that
produced the defects** — not under cleaned-up ones.

**This is deliberately not a repeat of Run 2.** The migration, the `.bak`, the containment boundary and
the Dredd citation already passed on real evidence; re-running them buys nothing. Run 3 is narrow and
adversarial.

---

## The one precondition that looks like a bug and is not

```
aprodaAldc.devRoot = "c:\_EphemeralWorkspace"          ← the "Florian Köll" segment is missing
```

**Leave it wrong.** This is the exact misconfiguration that supplied B-23 its plausible-but-wrong clone
target. Fixing it first would make the run prove nothing: the fix must hold *because the resolution is
captured before the bootstrap*, not because the fallback happens to point somewhere harmless.

The maintainer corrects it after Run 4, not before.

---

## Phase 0 — Preconditions

| Check | Required value |
|---|---|
| Test project tree | clean, branch `temp/temp-testing-for-aldc` |
| Project layout | root `aldc.yaml` **present**, `.github/aldc.yaml` **absent**, `.external/` **absent** |
| `aprodaAldc.source.mode` | `localFork` |
| `aprodaAldc.source.forkPath` | the fork under test |
| `aprodaAldc.bcquality.path` | **absent or empty** |
| `terminal.integrated.env.*.BCQUALITY_HOME` (Global) | **absent on all three platforms** |
| `aprodaAldc.devRoot` | `c:\_EphemeralWorkspace` — wrong on purpose, see above |
| Installed extension | `aprodaag.aproda-aldc-0.1.8-test.5` |

Then capture the baseline — **record the numbers, later criteria compare against them**:

```powershell
$real = 'c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda'
"real clone      : {0} files" -f (Get-ChildItem $real -Recurse -File -Force -EA SilentlyContinue).Count
"other clones    :"; Get-ChildItem 'c:\_EphemeralWorkspace' -Directory -Filter '*BCQuality*' -Recurse -Depth 2 -EA SilentlyContinue |
    ForEach-Object { "  $($_.FullName)" }
```

| ID | Criterion |
|---|---|
| **C1** | All rows of the table above hold. **Any deviation: stop and report** — a leaked `bcquality.path` or `BCQUALITY_HOME` would short-circuit the very rung under test |
| **C2** | Exactly **one** BCQuality clone exists on the machine, at `…\Florian Köll\BCQuality-Aproda`; its file count is recorded |

---

## Phase 1 — Apply Toolkit (B-24)

Run **`Aproda ALDC: Apply Toolkit`** on the test project. **Start a stopwatch.**

| ID | Criterion |
|---|---|
| **C3** | The command completes **without waiting for any dialog to be dismissed**. If a notification appears, it must not block progress — note its text and whether the command continued while it was open |
| **C4** | Wall-clock duration recorded. For reference: the syncer now enumerates ~606 files, dry-run ≈ 5 s. A multi-minute run is a finding |
| **C5** | The output names the applied layer source explicitly, and it is the **local fork** |
| **C6** | Migration performed: `.github/aldc.yaml` present, root `aldc.yaml` gone, `.external/` present with `README.md`, `*.code-workspace.bak` written |

---

## Phase 2 — Install / Update BCQuality (B-23, the blocker)

This is the heart of the run. Run **`Aproda ALDC: Install / Update BCQuality`**.

| ID | Criterion |
|---|---|
| **C7** | **No prompt appears.** The resolver already verifies the mounted clone, so the command must take the update path, not the clone path. A confirmation dialog here means the resolution failed — record its exact text |
| **C8** | **No new clone was created.** Re-run the `*BCQuality*` enumeration from Phase 0: the result must be **identical** to C2 — still exactly one clone, same path, same file count |
| **C9** | **The junction points at the real clone.** Assert the **target**, not existence: `(Get-Item '<project>\.external\bcquality' -Force).Target` → `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`. *This is the criterion Run 2 lacked, which is why the duplicate passed a 30-point list* |
| **C10** | Global `aprodaAldc.bcquality.path` is either still empty **or** set to the real clone — **never** to anything under `c:\_EphemeralWorkspace\BCQuality-Aproda` |
| **C11** | `Show BCQuality Status` reports a verified root equal to the real clone, and names which rung resolved it |

---

## Phase 3 — Settings hygiene (B-25, B-26)

| ID | Criterion |
|---|---|
| **C12** | Global `terminal.integrated.env.windows.BCQUALITY_HOME` is set to the real clone; **`linux` and `osx` carry no `BCQUALITY_HOME`** |
| **C13** | Apply Toolkit acted on the **test project**, not on the BCQuality clone or the fork. If a repository quick-pick appeared, record which entries it offered |

### Added after run 3 — the defects it uncovered (B-28 … B-31)

| ID | Criterion |
|---|---|
| **C17** | **No setting holds a path inside a repository.** `aprodaAldc.bcquality.path` and `BCQUALITY_HOME` must both be the **real clone** — never `<project>\.external\bcquality`. These are Global settings; a project-scoped value there poisons every other Aproda project on the machine (B-28) |
| **C18** | The two agree with each other. Run 3 found them pointing at **different** clones |
| **C19** | No `ELOOP` anywhere. `Get-Item '<project>\.external\bcquality' -Force` must succeed and its `Target` must be the real clone, not itself (B-28) |
| **C20** | **No "ALDC is not installed" prompt** on a fully migrated project — neither at startup nor on reopening the window. This fired on every window before (B-29) |
| **C21** | `Aproda ALDC: Validate Installation` runs and produces a verdict — not `spawn npm ENOENT` (B-30) |
| **C22** | The output log states what the BCQuality step decided. Quote the line. **Silence is a finding** (B-31) |

---

## Phase 4 — Negative test: the confirmation must actually fire

Run 2 never exercised the clone path deliberately. Force it:

1. Set Global `aprodaAldc.bcquality.path` to a path that does **not** exist, e.g.
   `c:\_EphemeralWorkspace\__bcq-does-not-exist`.
2. Run **`Install / Update BCQuality`**.
3. **Cancel** the dialog (press Esc — not a button).
4. Remove the setting again.

| ID | Criterion |
|---|---|
| **C14** | A modal confirmation appears and **names that exact path** in its detail text |
| **C15** | After cancelling: the directory was **not** created, no `git clone` ran, and `bcquality.path` still holds the value you set (the command must not have overwritten it) |
| **C16** | Pressing **Esc** is treated as cancel, identically to the Cancel button |

> Do **not** confirm the dialog. Cloning into a bogus path is not part of this run.

> **Run 3's report got this wrong and it matters.** The first attempt marked C14 FAIL ("no modal
> appeared") and derived a blocker from it. The modal *did* appear and was confirmed with **"Clone"**
> instead of Esc. An agent-driven harness cannot see modal dialogs — if you cannot observe the dialog,
> the verdict is **NOT-REACHED**, never FAIL. Inferring a product defect from your own blindness has now
> happened three times in this subsystem.

---

## Phase 5 — Leave the project in a known state

Report the final state; do not reset it yourself. The maintainer decides whether Run 4 gets a fresh
Straub or keeps this one.

---

## Report

Per `e2e-00-briefing.md` §4. Additionally state plainly, in one sentence each:

- Did a second clone appear anywhere? (C8)
- What exactly does the junction point at? (C9)
- Did anything write a Global setting you did not expect?
