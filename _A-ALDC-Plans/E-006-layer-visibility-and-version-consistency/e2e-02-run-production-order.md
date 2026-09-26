# Run 2 — the production order: new extension first, then the layer

> **Read [`e2e-00-briefing.md`](e2e-00-briefing.md) first.** It holds the environment facts and the hard
> rules — particularly the ones about junction deletion and script anchoring.
>
> **Precondition: the maintainer has reset the test project from the 1:1 backup.** Verify that before you
> start; do not perform or improvise the reset yourself.

**Purpose.** This is the real acceptance test for Block 4. The new extension is installed *first*, the
layer arrives *second* — the order an actual release must follow. Everything that Run 1 could not reach
is exercised here: junction creation, the `#bcquality` tool, the status UI, the Global `BCQUALITY_HOME`,
the disable path, and a real review that cites BCQuality.

---

## Phase 0 — Verify the reset

1. `git status --short` and `git branch --show-current` in the test project. Expect a clean tree on
   `temp/temp-testing-for-aldc`. **If the tree is dirty or the branch differs, stop and report.**
2. Confirm the pre-Block-4 layout is back: root `aldc.yaml` **present**, `.github/aldc.yaml` **absent**,
   `.external/` **absent**, no `*.code-workspace.bak`, and the workspace file's BCQuality root is
   `../BCQuality-Aproda` again.
3. **Capture and hash `StraubMedicalAGBase.code-workspace`.** B11 compares the `.bak` against this
   baseline, so it must be recorded before anything touches the file.
4. **Verify the layer source** — see the briefing's *"The layer source"* section. `aprodaAldc.source.mode`
   must be `localFork` and `aprodaAldc.source.forkPath` must point at the fork. **If `source.mode` is
   `managed`, stop immediately and report** — the run would apply the last *released* layer instead of
   the work under test, which is exactly how the previous attempt was invalidated.

| ID | Criterion |
|---|---|
| **B1** | Clean tree, correct branch, pre-Block-4 layout fully restored, workspace file hashed |
| **B1b** | `aprodaAldc.source.mode` = `localFork`, `source.forkPath` = the fork under test |

---

## Phase 1 — Confirm the new extension is active

**The VSIX has already been built and installed by the maintainer. You do not build or install
anything.** Your job here is only to *verify* that the running extension is the new one.

Background, so the version looks sane to you: the repository's `package.json` says `0.1.7`, which is
also what was installed originally. A rebuild at the same version is not distinguishable to VS Code, so
the build was made at a throwaway version `0.1.8-test.2` and the repository was reverted to `0.1.7`
afterwards. **The mismatch is intentional** — do not report it as a defect, and do not "fix" it. An
older throwaway build `0.1.8-test.1` also exists in `dist/`; it is superseded and must not be used.

```powershell
Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter 'aprodaag.aproda-aldc*' |
    Select-Object -ExpandProperty Name
```

| ID | Criterion |
|---|---|
| **B2** | The active extension is `aprodaag.aproda-aldc-0.1.8-test.2` |
| **B3** | The new commands exist: `Aproda ALDC: Show BCQuality Status` is offered in the Command Palette, and a `#bcquality` tool is reachable |
| **B4** | The fork's working tree carries no leftover version bump — `package.json` still reads `0.1.7` — and no `.vsix` is tracked |

**If B2 shows anything other than `0.1.8-test.2`, stop and report.** Everything after this point would
then be testing a different build and the whole run would be worthless.

---

## Phase 2 — What the extension does *before* the layer arrives

The project is still on the old layout. This phase checks that the new extension behaves sanely on a
not-yet-migrated project — the real state of every project at the moment the extension lands.

1. Open the test project (its `StraubMedicalAGBase.code-workspace`).
2. Run the command **`Aproda ALDC: Show BCQuality Status`**. Record the full quick-pick content.
3. Look for the BCQuality status-bar item. Record what it shows.

| ID | Criterion |
|---|---|
| **B5** | `Show BCQuality Status` runs and lists **every** resolver rung with a per-candidate verdict (`verified` / no entry point / not set) |
| **B6** | It shows the **declared** `aldc.yaml → home` and the **resolved** root **side by side** — they may differ, and that is exactly what this view exists to reveal |
| **B7** | The status-bar item exists and reflects the current state |
| **B8** | Nothing crashes, and no junction has been created yet in a project that has no `.external/` |

---

## Phase 3 — Deliver the layer, with the extension present

> **Use the extension's *Apply Toolkit* command, not `Start-Pull.ps1`.** This is deliberate and is what a
> developer at Aproda actually does (measured: ~98% of updates). It also avoids a known and accepted
> limitation that run 1 exposed: `Start-Pull.ps1` loads the **project's** copy of the sync engine, so on
> the very first Block-4 adoption it runs the *previous* version and needs a second pull to complete
> (finding **B-18**; the starter template is fixed for future projects, but an existing project never
> receives a refreshed starter — **T-40**). *Apply Toolkit* has never been affected: it runs the **fork's**
> engine. If you deviate and use `Start-Pull.ps1` anyway, say so and expect to pull twice.

Run **`Aproda ALDC: Apply Toolkit`** against the test project and capture the full output. Then reload
the VS Code window.

> **You cannot run this command yourself — hand it to the maintainer and wait.** It blocks on two
> interactions an agent cannot answer: `resolveTargetRepo()` raises a **quick-pick** because this
> workspace currently has two git roots (the project *and* the mounted `../../BCQuality-Aproda`), and
> `confirmGitHubChanges` raises a **warning with buttons**. Capture the state *before*, ask the
> maintainer to run the command, then capture the state *after*.
>
> **Do not improvise a substitute.** Running `Bootstrap-AprodaProject.ps1` directly would execute the
> same engine, but it would skip the extension's own command path — which is part of what this phase
> exists to test. If you end up doing it anyway for some reason, say so prominently in the report; a
> disclosed deviation is fine, a silent one makes the run worthless.

| ID | Criterion |
|---|---|
| **B9** | Apply Toolkit completes without an unhandled error |
| **B10** | `.github/aldc.yaml` exists with `toolkitRoot: ".github"`; the root `aldc.yaml` is gone |
| **B11** | `.external/README.md` exists; the workspace file mounts `.external`; a `.bak` was written and is byte-identical to the **Phase-0 baseline** you captured (not to some later intermediate state — that was finding **F2**, now fixed by taking the backup before the *first* rewrite) |
| **B12** | `BCQUALITY_HOME` is absent from the workspace file |
| **B13** | `agents/index.md`, `docs/copilot-reference.md`, `docs/bcquality.md` arrived — **in this single run** |
| **B13b** | The legacy sibling root's `search.exclude` / `files.watcherExclude` globs (`../../BCQuality-Aproda`) are **gone**, leaving only `bcquality/**` |

For **B11**, hash the `.bak` against the Phase-0 copy of the workspace file — do not compare by eye.

Now trigger the extension's junction reconcile with **`Aproda ALDC: Install / Update BCQuality`**.

> **This one you CAN run yourself** — it has no blocking prompt, only a closing information message. Use
> your VS Code command tool. If it fails or asks something you cannot answer, stop and hand it over
> rather than working around it.

| ID | Criterion |
|---|---|
| **B14** | `.external/bcquality` now exists **and is a reparse point**, not a real directory. Verify with `(Get-Item '.external\bcquality' -Force).LinkType` and `.Target` — the target must be `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` |
| **B15** | `BCQUALITY_HOME` is now a **Global** VS Code setting under `terminal.integrated.env.windows` (check the user `settings.json`, not the workspace file) |
| **B16** | `Show BCQuality Status` now reports a **verified** clone, names the rung it resolved from, and shows the junction as present |
| **B17** | The status-bar item switched to the active state |

---

## Phase 4 — Does it actually work for an agent?

This is the payoff. Everything above is plumbing.

1. **The consumption chain, by path.** Read, in order, and confirm each returns real content:
   `.external/bcquality/skills/entry.md` → the file it routes to (`skills/read.md`) →
   `skills/do.md` → one real knowledge file, e.g.
   `microsoft/knowledge/performance/use-setloadfields-for-partial-records.md` (frontmatter + body).
2. **The `#bcquality` tool.** Invoke it with `{ operation: "read", path: "skills/entry.md" }`. Then
   `{ operation: "list", path: "skills" }`. Then try to break it: `{ operation: "read", path: "../../../../Windows/win.ini" }`
   and an absolute path. Record the responses.
3. **Search hygiene.** Run a workspace-wide `grep_search` for an AL symbol that certainly exists in
   BCQuality's example files (the clone contains ~246 `.al` files). Count hits **under the mount**.
4. **A real review.** Invoke `@Dredd` on a small, real scope in this project. Read the output.

| ID | Criterion |
|---|---|
| **B18** | The full four-link chain resolves through the junction and returns real content |
| **B19** | `#bcquality` `read` and `list` both work against the resolved clone |
| **B20** | Path traversal and absolute paths are **rejected** by `#bcquality`, with a clear message and **no file content** |
| **B21** | `grep_search` returns **zero** hits under `.external/bcquality` — the exclude works, and the clone's example `.al` files do not pollute project searches |
| **B22** | The review records BCQuality as **active** and produces at least one finding backed by a knowledge-file citation with a resolvable `references[].path` |
| **B23** | The review does not block, error or loop |

For **B22**: open the cited path and confirm the file genuinely exists in the clone. A citation that does
not resolve is a hallucination, and catching one here is more valuable than a green run.

---

## Phase 5 — The disable path (destructive-behaviour check)

The reconcile is specified as **bidirectional**: switching BCQuality off must *remove* an existing
junction, not merely stop creating one. And that removal must never harm the real clone.

1. **First, record a fingerprint of the real clone** at
   `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`: total file count and the hash of one known
   file. You will compare after.
2. Edit `.github/aldc.yaml` → `external.bcquality.enabled: false`.
3. Trigger the reconcile again (same command as in Phase 3). Reload if needed.

| ID | Criterion |
|---|---|
| **B24** | `.external/bcquality` is **gone** |
| **B25** | **The real clone is untouched** — same file count, same hash. This is the single most important criterion in this run |
| **B26** | `.external/` and its tracked `README.md` still exist (the wrapper is not the junction) |
| **B27** | `Show BCQuality Status` and the status-bar item report the disabled state |

4. Set `enabled` back to `auto`, reconcile again, and confirm the junction returns.

| ID | Criterion |
|---|---|
| **B28** | The junction is re-created and verified again after switching back to `auto` |

---

## Phase 6 — Idempotency and close-out

1. Run **Apply Toolkit** a second time — again a **maintainer action** (same two prompts as in Phase 3).
   Capture the state before and after yourself.

| ID | Criterion |
|---|---|
| **B29** | `Init 5: project layout already current -- nothing to migrate.`, the workspace file is byte-identical, and no second `.bak` appears |

2. Record `git status --short` and `git diff --stat` in the test project. **Do not commit and do not
   clean up** — the maintainer decides what happens to the project.
3. Confirm the fork's working tree is still clean (the `package.json` bump was reverted in Phase 1).

| ID | Criterion |
|---|---|
| **B30** | The fork's working tree is clean — no leftover version bump, no stray files, no `.vsix` committed |

The test build stays installed until the maintainer decides otherwise. **Do not uninstall it and do not
reinstall `0.1.7`** — that is the maintainer's call, not yours.

---

## Final report

Per the contract in the briefing: one line per criterion `B1`–`B30`, then the narrative, findings and
open questions.

Close with a direct answer to:

> **Is Block 4 ready to be released to the fleet — and does the evidence support "extension first" as a
> hard gate, or merely as a recommendation?**

Base that on what you measured in this run together with Run 1's result. If anything in Phase 4 or
Phase 5 failed, say plainly that it is not ready. A qualified "yes, but" is fine; a vague one is not.
