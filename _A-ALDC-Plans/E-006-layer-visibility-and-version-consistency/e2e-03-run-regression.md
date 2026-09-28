# Run 3 — regression test for the run-2 blockers (B-23 … B-26)

> **Read [`e2e-00-briefing.md`](e2e-00-briefing.md) first** — environment facts, hard rules, and §5
> (the user-settings reset). This file only adds what is specific to Run 3.

**Purpose.** Run 2 scored 26/30 and found four defects. All four are fixed and committed
(`517cd74`, `83a4227`). This run proves the fixes on the same project, under the **same conditions that
produced the defects** — not under cleaned-up ones.

**Runs 3.2 and 4.2 then found five more** (B-28 … B-32), and driving the validator's warning baseline
to zero uncovered two more still (B-35 … B-37). Everything since test.7 is **unproven in production**:
this run is where it gets proven, or does not.

**Four fixes have never run outside a unit test.** They carry their own criteria below, and two of them
can plausibly fail:

| | Why it might fail here |
|---|---|
| **B-35** — the inherited TLS override is stripped from child processes | `npm install` now verifies certificates. Behind a TLS-intercepting proxy it may fail where it previously "succeeded". **That is the announced residual risk** — if it fails, that is information, not a surprise |
| **B-37** — `**/` spans zero directories in the syncer | Only ever dry-run. Two files must now actually arrive |
| **B-32** — a configured path is no longer silently overwritten | Unit test only |
| **B-33** — Phase 4 removes the junction first | The negative test has never once reached its own dialog |

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
| Installed extension | `aprodaag.aproda-aldc-0.1.8-test.8` |

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
| **C3** | The command completes **without waiting for an advisory notification to be dismissed**. The *"uncommitted changes under .github"* prompt is **not** one of those — it is a deliberate Continue/Cancel gate and is expected to block (B-24 only removed the *advisory* warnings). Record what appeared and which kind it was |
| **C4** | Wall-clock duration recorded. For reference: the syncer now enumerates ~606 files, dry-run ≈ 5 s. A multi-minute run is a finding |
| **C5** | The output names the applied layer source explicitly, and it is the **local fork** |
| **C6** | Migration performed: `.github/aldc.yaml` present, root `aldc.yaml` gone, `.external/` present with `README.md`, `*.code-workspace.bak` written |
| **C24** | **The two long-missing layer files arrived** (B-37): `.github/CHANGELOG.aproda.md` and `.github/onboarding.aproda.md` both exist. They were silently withheld from every project until now, because the syncer's `**/` never matched a root-level path. **This is the first real pull after that fix** — a dry-run is not evidence |
| **C25** | The resolved-file count in the output is **137**, not 135. Record the number you actually see |

---

## Phase 2 — Install / Update BCQuality (B-23, the blocker)

This is the heart of the run. Run **`Aproda ALDC: Install / Update BCQuality`**.

| ID | Criterion |
|---|---|
| **C7** | **No prompt appears.** The resolver already verifies the mounted clone, so the command must take the update path, not the clone path. A confirmation dialog here means the resolution failed — record its exact text |
| **C8** | **No new clone was created.** Re-run the `*BCQuality*` enumeration from Phase 0: same single clone, same path. A small file-count delta is expected and benign — `git fetch` writes `.git/FETCH_HEAD`; what must not change is the number of clones |
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
| **C21** | `Aproda ALDC: Validate Installation` runs and produces a verdict — not `spawn npm ENOENT` and not `spawn EINVAL` (B-30). Both earlier runs died here |
| **C26** | **`npm install` still completes with certificate verification enabled** (B-35). The `NODE_TLS_REJECT_UNAUTHORIZED` warning that appeared in the previous run's output must be **gone**. If instead npm fails with a certificate or network error, **report it as-is and do not work around it** — that is the announced residual risk of the fix, and the remedy is `NODE_OPTIONS=--use-system-ca`, never restoring the override |
| **C27** | The validator reports the project's **pre-existing** warning count and **no fork-only warnings** — no `skills/index.md links a skill that does not exist` and no `readme.aproda.md's inventory references …` (B-36/B-37). *`straub-medical-ag-base` has carried four AL naming warnings since 2026-09-24 (T-31); those are the project's own source and are **not** a failure of this criterion* |
| **C31** | **The extension update is offered before the layer update** (B-38). If both are due in the same session, the extension notification must appear and be answered first. If only one is due, note which |
| **C22** | The output log states what the BCQuality step decided. Quote the line. **Silence is a finding** (B-31). **Read the channel immediately after Apply Toolkit** — do not reload the window, install a VSIX, or let the extension host restart in between; any of those recreates the channel and destroys the evidence |

---

## Phase 4 — Negative test: the confirmation must actually fire

**Run 3.2 found this phase could not fire its own dialog (B-33).** Once Phases 1–2 have run, the
`.external/bcquality` junction resolves no matter what garbage `bcquality.path` holds, so the command
never reaches the "nothing resolved, offer to clone" branch.

That failure is now put to work: the same setup tests **two** different fixes, in order. Do not skip
step A — with the junction already removed it can no longer be tested.

### Step A — junction still intact: a configured path must survive (B-32)

1. Set Global `aprodaAldc.bcquality.path` to `c:\_EphemeralWorkspace\__bcq-does-not-exist` and confirm
   it saved.
2. Run **`Install / Update BCQuality`**. The junction still resolves, so the command will succeed
   against the real clone.

| ID | Criterion |
|---|---|
| **C28** | The command **does not silently rewrite** `aprodaAldc.bcquality.path`. After it finishes, the setting still reads `c:\_EphemeralWorkspace\__bcq-does-not-exist`. *Run 3.2 found it overwritten with no confirmation and no log line* |
| **C29** | The mismatch is **surfaced** — a warning naming that the configured path did not resolve, plus a log line. Quote both. Silently doing the right thing to a wrong setting is still silent |
| **C30** | No clone was created at the bogus path; still exactly one clone on the machine |

### Step B — junction removed: the clone confirmation (B-33)

**Remove the junction** — link only, never recursive (briefing rule 5):

```powershell
(Get-Item '<project>\.external\bcquality' -Force).Delete()   # removes the link, NOT the clone
```

Then verify the real clone is still intact (`Test-Path` on it, file count unchanged) **before**
continuing. If it is not, stop immediately.

1. Leave `aprodaAldc.bcquality.path` on the bogus path from step A.
2. Run **`Install / Update BCQuality`**.
3. **Cancel** the dialog (press Esc — not a button).
4. Remove the setting again, then re-run `Install / Update BCQuality` to restore the junction.

| ID | Criterion |
|---|---|
| **C14** | A modal confirmation appears and **names that exact path** in its detail text |
| **C15** | After cancelling: the directory was **not** created, no `git clone` ran, and `bcquality.path` still holds the value you set |
| **C16** | Pressing **Esc** is treated as cancel, identically to the Cancel button |
| **C23** | After step 4 the junction exists again and its `Target` is the real clone |

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
- Did `CHANGELOG.aproda.md` and `onboarding.aproda.md` actually arrive, and what file count did the
  pull report? (C24, C25)
- Did `npm install` complete with certificate verification on, and is the
  `NODE_TLS_REJECT_UNAUTHORIZED` warning gone? (C26)
- What is the validator's warning count, verbatim? (C27)

> **Two standing rules, both earned the hard way in this subsystem.**
>
> **A criterion you could not observe is `NOT-REACHED`, never `FAIL`.** An agent-driven harness cannot
> see modal dialogs. Inferring a product defect from your own blindness has happened three times here.
>
> **Never repair the environment to make a criterion pass.** A previous attempt reached "0 warnings" by
> hand-copying two files into the test project — a result no user could reproduce, and it hid the
> genuine defect underneath (B-37). If something is missing, report it missing.
