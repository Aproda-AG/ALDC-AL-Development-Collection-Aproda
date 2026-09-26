# Run 2 result — production order (new extension first, then the layer)

Executed 2026-09-25 against `aprodaag.aproda-aldc-0.1.8-test.1` in the live, interactive VS Code
window (agent had no native-UI capture; two steps required the maintainer). No `git push`, no branch
change, no commit was made in either repository, per the briefing's hard rules.

## Result

| ID | Verdict | Evidence |
|---|---|---|
| B1 | PASS | `git status --short` → only untracked `.github/_e2e-test/`; branch `temp/temp-testing-for-aldc`; root `aldc.yaml` present, `.github/aldc.yaml` absent, `.external` absent, no `.bak`; workspace file hashed (`218FDC36…BE65CC1`, saved as `phase0-baseline.code-workspace`) |
| B2 | PASS | `code --list-extensions --show-versions` → `aprodaag.aproda-aldc@0.1.8-test.1` (both 0.1.7 and 0.1.8-test.1 present on disk, but the active one is 0.1.8-test.1) |
| B3 | PASS | `aprodaAldc.showBcQualityStatus` command exists and runs; `#bcquality` (`aprodaAldc_bcquality`) tool is reachable and callable |
| B4 | PASS (with a caveat) | Fork `package.json` = `0.1.7`, no tracked `.vsix` (`dist/` is gitignored). **Caveat**: the fork tree is *not* fully clean — `_A-ALDC-Plans/.../e2e-02-run-production-order.md` shows as modified (`M`). This pre-existed before this run started (we never touched the fork) and is unrelated to the extension build; flagged, not treated as a defect of Block 4 |
| B5 | PARTIAL | Could not capture the native quick-pick UI content directly (no screenshot/keyboard tool for native VS Code pickers). Used the equivalent resolver data via `#aldcConfiguration` as a substitute: it reports every candidate the resolver walks (`resolvedFrom`, `verified`) — functionally the same data the picker shows, but not the literal UI capture the phase asks for |
| B6 | PARTIAL (same limitation as B5) | `#aldcConfiguration` showed declared `home: "../../BCQuality-Aproda"` vs `resolvedHome: "c:\...\BCQuality-Aproda"` side by side, before Apply Toolkit ran |
| B7 | NOT-REACHED | No tool available to read the native VS Code status-bar item's rendered text |
| B8 | PASS | Nothing crashed; `.external` did not exist yet at this point in the run |
| B9 | PASS (maintainer-run) | Maintainer confirmed Apply Toolkit "succeeded" / "init done" with no error |
| B10 | **FAIL** | After Apply Toolkit: root `aldc.yaml` **still present**, `.github/aldc.yaml` **still absent**. The layout migration did not happen |
| B11 | **FAIL** | `.external/README.md` **absent**; `StraubMedicalAGBase.code-workspace` hash **unchanged** from the Phase-0 baseline (no rewrite happened at all); **no `.bak` was written** |
| B12 | **FAIL** (moot) | Workspace file untouched, so `BCQUALITY_HOME` is exactly where it was before (still present in the old form under `terminal.integrated.env.*` at the *workspace* level, in addition to appearing correctly at User level — see B15) |
| B13 | **FAIL** | `.github/agents/index.md`, `.github/docs/copilot-reference.md`, `.github/docs/bcquality.md` do **not** exist |
| B13b | **FAIL** | Workspace file untouched — the legacy `../../BCQuality-Aproda` sibling root and its `search.exclude`/`files.watcherExclude` entries are still present |
| B14 | PASS | `.external\bcquality` is a `Junction` (`(Get-Item … -Force).LinkType` = `Junction`), `.Target` = `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` — correct |
| B15 | PASS | User `settings.json` → `terminal.integrated.env.windows/linux/osx.BCQUALITY_HOME` = `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` — a real **Global** setting |
| B16 | PARTIAL (same UI-capture limitation as B5) | `#aldcConfiguration` confirmed `verified: true`, `resolvedFrom` naming a rung, junction present — the data the picker would show, not the picker itself |
| B17 | NOT-REACHED | Same as B7 — no tool to read the status-bar rendering |
| B18 | PASS | Full chain read end-to-end: `skills/entry.md` → `skills/read.md` → `skills/do.md` → `microsoft/knowledge/performance/use-setloadfields-for-partial-records.md`, all real content with frontmatter |
| B19 | PASS | `#bcquality {operation: read, path: skills/entry.md}` and `{operation: list, path: skills}` both returned real data (5 entries: do.md, entry.md, read.md, README.md, write.md) |
| B20 | PASS | Path traversal (`../../../../Windows/win.ini`) → `{"status":"invalidPath","message":"Path escapes the BCQuality clone root."}`; absolute path (`C:\Windows\win.ini`) → `{"status":"invalidPath","message":"Path must be relative to the BCQuality clone root, not absolute."}`. No content leaked either time |
| B21 | PASS (narrowly) | `grep_search` scoped to `.external/bcquality/**` → 0 hits for `SetLoadFields`. **But** a workspace-wide search (no exclude) surfaced 8 hits from the *separate, still-mounted* `BCQuality-Aproda` workspace root (a direct consequence of B13b failing — the legacy mount was never removed) |
| B22 | PASS | Dredd ran against `Base/SRC/Azure Storage Proxy/StorageProxyVerifier.Codeunit.al`, reported BCQuality active (`resolvedFrom: setting`, `mounted: true`), one minor finding citing `microsoft/knowledge/performance/use-textbuilder-for-string-concatenation-in-loops.md`. Citation verified independently via `#bcquality read` — genuine, resolvable, not a hallucination |
| B23 | PASS | Dredd completed with a clean verdict (`PASS_WITH_FINDINGS`), no block/error/loop. It self-reported one deviation: `knowledge-index.json` was absent in the clone, so it fell back to direct file reads instead of the documented index-based retrieval — a real, if minor, gap worth tracking separately from this E2E run |
| B24 | **FAIL / CONFOUNDED** | After setting `enabled: false` + reconcile, the junction **did not disappear**. Root cause found: a pre-existing **global** VS Code setting `aprodaAldc.bcquality.path` (already pointing at the clone, present on this machine before this run) outranks `aldc.yaml`'s `enabled: false` in the resolver's precedence order. After clearing that setting (with the user's permission), the junction *still* did not disappear — because the resolver's next-highest rung, the still-present legacy **`workspaceFolder`** mount (`../../BCQuality-Aproda`, a direct consequence of B10/B13b failing), also resolves successfully and *also* outranks `enabled: false` |
| B25 | PASS | Real clone fingerprint unchanged throughout: 490 files, `skills/entry.md` SHA-256 `44590D0A…273C55A` both before and after — **the junction-removal failure did not touch the real clone**, which is the one property that must never break |
| B26 | N/A (moot — B24 never fired) | `.external/README.md` never existed to begin with (B11), so this criterion cannot be meaningfully evaluated on its own |
| B27 | NOT-REACHED | Same UI-capture limitation as B7/B17 |
| B28 | PASS (trivially — nothing to re-create since it never disappeared) | `enabled` reset to `"auto"`; junction still present and `verified: true` (`resolvedFrom: workspaceFolder`) |
| B29 | PASS (with an evidence gap) | Second Apply Toolkit run: workspace-file hash **identical** to Phase-0 baseline, no new `.bak`, `git status`/`git diff --stat` unchanged. Idempotent at the file level. **Gap**: I did not capture the literal `Init 5: project layout already current -- nothing to migrate.` log line — the maintainer ran the command directly and reported "succeeded again" without pasting the console text |
| B30 | PASS (same caveat as B4) | Fork `package.json` still `0.1.7`, no tracked `.vsix`. Same pre-existing, unrelated `M` on the plan doc noted at B4 |

## What actually happened

Run 2 split into two distinct halves with a hard line between them at Phase 3.

**Phases 0–2 went as scripted.** The reset was verified, the new extension build (`0.1.8-test.1`) was
confirmed active over the CLI (`code --list-extensions --show-versions`), and the `#bcquality` /
`#aldcConfiguration` tools were reachable and gave real resolver data even before any migration ran —
because the project already had a *legacy, still-working* sibling mount (`../../BCQuality-Aproda`) from
before Block 4. That pre-existing mount turned out to be the thread that unravels the rest of the run.

**Phase 3 is where the run diverges from the script.** The maintainer ran `Aproda ALDC: Apply Toolkit to
Project (per Repo)` once, through the two required prompts (repo quick-pick, GitHub-changes
confirmation), and it reported success. But on disk, only one thing changed: `.external\bcquality` (the
junction) came into existence. Nothing else did — `aldc.yaml` was not moved to `.github/`, no
`.external/README.md` was written, no `docs/bcquality.md` or `agents/index.md` arrived, no `.bak` was
created, and the workspace file's hash never moved from the Phase-0 baseline. The root `aldc.yaml`'s
`mtime` did change (same instant as the junction), but a `git diff` on it showed **zero** content change
— it was rewritten with byte-identical content, which reads like a no-op save rather than a real
migration pass.

The most plausible explanation, from reading `root aldc.yaml` itself: that file *already* declares
`toolkitRoot: ".github"` even while still living at the repository root. If the migration's "is this
project already on the new layout?" check inspects the *value* of `toolkitRoot` rather than the *file's
own location*, it would conclude "nothing to migrate" on a project whose `aldc.yaml` simply hasn't been
renamed/moved yet but already carries the target-state value for that one key. That would explain
precisely the observed split: the layout migration (Init 5, the layer/version-consistency half of Block
4) silently no-ops, while the junction reconcile (a separate code path, evidently gated only on
`external.bcquality.enabled`) runs and succeeds independently. This is a hypothesis grounded in what the
file contains, not a confirmed root cause — I did not have access to the extension's runtime logs to
verify it directly.

**Phase 4 (the actual payoff) passed cleanly and convincingly.** The full four-link knowledge chain
resolved through the junction with real content, the `#bcquality` tool's `read`/`list` operations worked,
and — most importantly for trustworthiness — both a path-traversal attempt and an absolute-path attempt
were rejected with a clear message and **zero file content** leaked. A real Dredd audit against a live
project file ran to completion, correctly detected BCQuality as active, and produced one citation-backed
finding; the citation was independently re-read through `#bcquality` and is genuine, not a hallucination.
Search hygiene, narrowly scoped to `.external/bcquality/**`, showed zero pollution — but a workspace-wide
search still surfaced hits from the *other*, legacy-mounted BCQuality root, a direct symptom of the
Phase-3 migration never having removed that mount.

**Phase 5 (the disable path) is the most consequential finding of this run.** Flipping
`external.bcquality.enabled` to `false` and reconciling did not remove the junction. Chasing this down
surfaced a genuine design problem, not a one-off glitch: the resolver walks a fixed precedence chain
(`setting` → `workspaceFolder` → `environment` → `devRoot` → `aldcYaml`), and **only the last rung reads
`enabled`.** Any of the four higher-precedence rungs — a stray per-machine setting, a leftover legacy
workspace mount, an environment variable, or the dev-root convention — will resolve BCQuality as active
regardless of what the project's own `aldc.yaml` says. In this run *two* such rungs were in play at once
(first a pre-existing global `aprodaAldc.bcquality.path` setting, then, after clearing it with the user's
permission, the still-present legacy workspace mount from the failed Phase-3 migration). The one thing
that did hold throughout every step of this — including two full reconcile cycles with the switch
flipped both ways — is the real clone itself: file count and hash never moved. Junction manipulation,
however broken its trigger condition, never touched the thing it must never touch.

**Phase 6** showed the *junction* side of the system is genuinely idempotent — a second Apply Toolkit run
left the workspace file byte-identical with no new `.bak` — but this is a weak signal given that no real
migration ran the first time either; "nothing changed the second time" and "nothing changed the first
time, for the wrong reason" are not distinguishable from the file-system evidence alone.

**Environment note, disclosed as instructed**: two live-environment states were not part of the "verified
2026-09-25" facts table and were discovered mid-run: (1) a global `aprodaAldc.bcquality.path` setting
already pointed at the clone before this run started; (2) editing `settings.json` directly while VS Code
is running does not stick — the editor rewrites the file from its in-memory state, which is why we had
to ask the maintainer to clear the setting through the Settings UI instead. Both are documented above at
the exact point they affected a criterion, and the global setting was restored to its prior intent by the
user afterward (the user cleared it a second time themselves after observing it reappear; whether it
reappeared via VS Code's own settings-sync behavior or via the extension's own startup/doctor check
running in the background — `aprodaAldc.startupCheck.enabled: true` was set for this project — was not
established with certainty within this run's scope).

## Findings

- **Blocker** — B10/B11/B12/B13/B13b: the layer-visibility layout migration (Init 5) did not run during
  Apply Toolkit in this environment, even though the command reported success. This is the exact defect
  category Block 4 was supposed to fix (layer visibility / version consistency), reproduced live. Root
  cause is a hypothesis (see narrative above), not confirmed against source — needs the extension's own
  logs or a source read of the migration-detection logic to close out.
- **Blocker** — B24: `external.bcquality.enabled: false` is not an effective master switch. Any
  higher-precedence resolver rung (user setting, workspace-folder mount, environment variable, dev-root
  convention) silently overrides it, with no warning surfaced to the user that the "disable" they just
  configured has had no effect. This contradicts the aldc.yaml's own comment, which calls `enabled` "the
  explicit off switch." If the intent is "off means off, full stop," the resolver needs to check `enabled`
  first, at the top, not fold it into the lowest-precedence rung's data.
- **Major** — B21/B13b: because the migration never runs, a project can carry an indefinitely-stale
  legacy sibling mount whose `.al` example files then leak into ordinary workspace searches. The
  junction's own exclude works fine (0 hits); the legacy mount's exclude configuration is whatever it was
  before Block 4 and was never touched.
- **Minor** — B5/B6/B7/B16/B17/B27: I have no tool to observe native VS Code quick-pick content or
  status-bar text. Every criterion that depends on reading that UI directly is only as good as the
  `#aldcConfiguration`/`#bcquality` proxy data I substituted — which is real and traceable, but is not
  what the phase asked for. This is a test-harness gap on my side, not a product defect; a human should
  independently glance at the actual picker/status bar before this ships.
- **Minor** — Dredd's own Step 0 fell back to direct knowledge-file reads because `knowledge-index.json`
  was absent from the clone and it had no terminal access in its subagent context to build one. Not a
  Block-4 defect (the index is a BCQuality-repo concern, not this project's), but worth tracking since it
  means every fresh clone currently forces every review to skip the documented fast path.
- **Nit** — the fork's own working tree carries an uncommitted `M` on
  `e2e-02-run-production-order.md` (visible at B4 and B30) that pre-dates this run and was never touched
  by it. Flagged per instruction, not treated as a defect.
- **Passed but felt wrong**: B21 passing "on paper" (0 hits under `.external/bcquality`) while the
  broader workspace search still leaks 8 hits from the legacy mount is exactly the kind of green check
  that hides a real problem — noted per the briefing's explicit ask for this.

## Open questions

1. Is the Phase-3 migration no-op a genuine bug in the "already on new layout?" detection (my
   hypothesis: it reads `toolkitRoot`'s *value* rather than checking whether `aldc.yaml` itself lives at
   `.github/aldc.yaml`), or did something about this specific project's history (root `aldc.yaml`
   pre-declaring `toolkitRoot: ".github"` before ever being moved) make it look, to the migration script,
   like a project that had already migrated? This needs a source read of the migration/Init-5 detection
   logic or the extension's log output to resolve — neither was available to me in this session.
2. Given finding B24, what is the *intended* precedence between `aldc.yaml`'s `enabled: false` and the
   four higher-precedence resolver rungs? If a developer's personal `aprodaAldc.bcquality.path` should
   always win (e.g., for local override during BCQuality-repo development), that's a legitimate design —
   but it should be visible in the status UI/picker as "disabled by project, but overridden by your local
   setting," not silently resolve as if the project-level switch were never touched.
3. Was the reappearance of `aprodaAldc.bcquality.path` after the user's first deletion caused by VS
   Code's own settings-file rewrite behavior, by Settings Sync, or by the extension's own
   `aprodaAldc.startupCheck` doing an autonomous repair? This affects how much to trust manual
   "disable and reconcile" testing on any machine that has ever had BCQuality set up before.
4. I could not observe the native quick-pick/status-bar UI at all (B5–B8, B16, B17, B27). Is there a
   supported way for an agent to capture that content (e.g., an output channel mirror, a `--verbose` log
   file), or is a human glance at the actual UI a permanent, unavoidable step in validating this feature?
5. B29's literal `Init 5: project layout already current -- nothing to migrate.` message was not
   captured verbatim — only inferred from unchanged file state. Worth a literal-text capture in any
   follow-up run, since given finding #1, "no message at all" and "the expected no-op message" would look
   identical from the file system alone.

## Is Block 4 ready to release?

**No — not as observed in this run.** The part of Block 4 this run was built to validate twice —
migrating an existing project's layout, and making the disable switch actually disable — did not work in
this execution. The junction-creation and the read-side of the knowledge chain (Phase 4) are genuinely
solid: real content, real citation, real rejection of path traversal, and the one property that must
never break (the real clone) never did. But Phase 3's core promise (an existing project gets migrated
when the extension lands) and Phase 5's core promise (flipping the switch off actually turns it off) both
failed to reproduce as specified, and the second failure has a root cause (resolver precedence) that is
independent of anything specific to this run's environment quirks — it will recur on any machine or
project carrying a higher-precedence override, which is exactly the kind of thing real developer machines
accumulate over time.

On **"extension first" as a hard gate vs. a recommendation**: this run does not speak to ordering at all
— by design, Run 2 only exercises the production order. Combine with Run 1's result (which specifically
tests what happens when the layer arrives before the extension) to answer that question; Run 2 alone
supports neither a stronger nor a weaker gate recommendation than what Run 1 already established.

Recommend: fix the two blockers above (migration-detection no-op, `enabled` precedence), re-run Phase 3
and Phase 5 clean (ideally on a machine with no prior BCQuality-related global settings at all, to remove
the environment confound), and only then consider this ready for the fleet.
