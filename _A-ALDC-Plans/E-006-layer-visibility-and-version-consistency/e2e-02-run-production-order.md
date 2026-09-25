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

| ID | Criterion |
|---|---|
| **B1** | Clean tree, correct branch, pre-Block-4 layout fully restored, workspace file hashed |

---

## Phase 1 — Build and install the new extension

The installed build is `0.1.7` and the repo's `package.json` also says `0.1.7`, so a rebuild alone is
**not** version-distinguishable — VS Code would not treat it as an update and you might silently test
the old code. A temporary version bump solves that. It is reverted at the end of this run.

Work in `<fork>\tools\aproda-vscode-extension`.

1. **Temporarily** set `version` in `package.json` to `0.1.8-test.1`. Change nothing else.
2. `npm test` — all suites must pass before you package anything. If any fail, **stop and report**.
3. `npm run package` → produces a `.vsix`. Record its exact filename.
4. Install it:
   `code --install-extension <path-to-vsix> --force`
5. **Reload / restart VS Code**, then confirm the active version:
   `Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter 'aprodaag.aproda-aldc*' | Select-Object -ExpandProperty Name`
6. **Revert `package.json` to `0.1.7`** (`git checkout -- package.json` in the fork). The bump was only
   to force the install; it must not survive in the repository. Verify the fork's `git status` is clean
   afterwards.

| ID | Criterion |
|---|---|
| **B2** | `npm test` passes all suites |
| **B3** | The VSIX installs and VS Code reports `aprodaag.aproda-aldc-0.1.8-test.1` as active |
| **B4** | The fork's `package.json` is back at `0.1.7` and the fork's working tree is clean |

> If the extension cannot be installed for policy reasons, fall back to launching an **Extension
> Development Host** (F5) from the fork and opening the test project inside it — then say so in the
> report, because it is a less faithful test.

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

| ID | Criterion |
|---|---|
| **B9** | Apply Toolkit completes without an unhandled error |
| **B10** | `.github/aldc.yaml` exists with `toolkitRoot: ".github"`; the root `aldc.yaml` is gone |
| **B11** | `.external/README.md` exists; the workspace file mounts `.external`; a `.bak` was written and is byte-identical to the **Phase-0 baseline** you captured (not to some later intermediate state — that was finding **F2**, now fixed by taking the backup before the *first* rewrite) |
| **B12** | `BCQUALITY_HOME` is absent from the workspace file |
| **B13** | `agents/index.md`, `docs/copilot-reference.md`, `docs/bcquality.md` arrived — **in this single run** |
| **B13b** | The legacy sibling root's `search.exclude` / `files.watcherExclude` globs (`../../BCQuality-Aproda`) are **gone**, leaving only `bcquality/**` |

For **B11**, hash the `.bak` against the Phase-0 copy of the workspace file — do not compare by eye.

Now trigger the extension's reconcile — via **`Aproda ALDC: Install / Update BCQuality`** or
**Apply Toolkit**, whichever the extension offers. Record which you used.

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

1. Run **Apply Toolkit** a second time.

| ID | Criterion |
|---|---|
| **B29** | `Init 5: project layout already current -- nothing to migrate.`, the workspace file is byte-identical, and no second `.bak` appears |

2. Record `git status --short` and `git diff --stat` in the test project. **Do not commit and do not
   clean up** — the maintainer decides what happens to the project.
3. Confirm the fork's working tree is still clean (the `package.json` bump was reverted in Phase 1).

| ID | Criterion |
|---|---|
| **B30** | The fork's working tree is clean — no leftover version bump, no stray files, no `.vsix` committed |

Optionally uninstall `0.1.8-test.1` and reinstall `0.1.7` if the maintainer wants the workstation back
in its prior state — **ask first**, do not decide this yourself.

---

## Final report

Per the contract in the briefing: one line per criterion `B1`–`B30`, then the narrative, findings and
open questions.

Close with a direct answer to:

> **Is Block 4 ready to be released to the fleet — and does the evidence support "extension first" as a
> hard gate, or merely as a recommendation?**

Base that on what you measured in this run together with Run 1's result. If anything in Phase 4 or
Phase 5 failed, say plainly that it is not ready. A qualified "yes, but" is fine; a vague one is not.
