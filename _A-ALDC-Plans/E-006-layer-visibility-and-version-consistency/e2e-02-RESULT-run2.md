# Run 2 — production order — Result

> Against [`e2e-02-run-production-order.md`](e2e-02-run-production-order.md), briefing in [`e2e-00-briefing.md`](e2e-00-briefing.md).
> Executed 2026-09-25. Reporting per the briefing's contract §4.

## Result

| ID | Verdict | Evidence (short) |
|---|---|---|
| B1 | PASS | `git status --short` clean except untracked `.github/_e2e-test/`; branch `temp/temp-testing-for-aldc`; root `aldc.yaml` present, `.github/aldc.yaml` absent, `.external` absent, no `.bak`. Baseline hash captured: `218FDC36…5CC1`. |
| B1b | PASS | User settings: `aprodaAldc.source.mode = "localFork"`, `source.forkPath = c:\_EphemeralWorkspace\Florian Köll\ALDC-AL-Development-Collection-Aproda`. |
| B2 | PASS | `.vscode\extensions` has `-0.1.7`, `-0.1.8-test.1`, `-0.1.8-test.2`; `.obsolete` marks the first two obsolete → active = `-0.1.8-test.2` (confirmed via its own `package.json`). |
| B3 | PASS | Active extension's `package.json` declares command `aprodaAldc.showBcQualityStatus` ("Show BCQuality Status") and languageModelTool `aprodaAldc_bcquality` (`#bcquality`). Both callable at runtime (used throughout this run). |
| B4 | PASS | Fork `tools/aproda-vscode-extension/package.json` = `0.1.7`, `git diff` on that file shows no version-field change; no `.vsix` tracked. *Caveat:* fork working tree was NOT fully clean (pre-existing unrelated uncommitted changes — briefing docs, several `.ts` sources, a leftover `e2e-02-RESULT-run1.md`); not caused by this run, not a version/vsix artifact, but worth the maintainer's attention. |
| B5 | PASS | `Show BCQuality Status` quick-pick (pre-layer) listed every resolver rung with its own verdict (✓/⊘): VS Code setting (not set), Mounted workspace folder (✓ verified), Mounted workspace folders-plural (⊘), `$BCQUALITY_HOME` (⊘ not set), `<devRoot>/…` (⊘ directory missing), `aldc.yaml → home` (✓ verified). |
| B6 | PASS | Same screen showed declared (`../../BCQuality-Aproda`, relative) and resolved (absolute, verified) side by side. |
| B7 | PASS | Status bar showed `✓ BCQuality`, tooltip named the resolved root and rung. |
| B8 | PASS | No crash; `.external` still absent after the status check; no `.bak` yet. |
| B9 | PASS | Apply Toolkit completed: *"Aproda ALDC initialization completed using the local fork at …ALDC-AL-Development-Collection-Aproda."* |
| B10 | PASS | `.github\aldc.yaml` present with `toolkitRoot: ".github"`; root `aldc.yaml` gone. |
| B11 | PASS | `.bak` SHA256 = `218FDC36…5CC1`, **exact match** to the Phase-0 baseline (not some later state). |
| B12 | PASS | Workspace file's `terminal.integrated.env.windows` block (which held `BCQUALITY_HOME`) is gone entirely. |
| B13 | PASS (nuance) | `.github/agents/index.md` and `.github/docs/copilot-reference.md` present but dated **24.09** (already delivered by Run 1's earlier sync, left untouched = idempotent no-op); `.github/docs/bcquality.md` dated **today**, genuinely new. All three exist under `.github/` (correct `toolkitRoot`), all gitignored. |
| B13b | PASS | Workspace file's `search.exclude`/`files.watcherExclude` now only `bcquality/**`; the legacy `../../BCQuality-Aproda` globs are gone. Folder mount switched from the sibling root to `.external` ("BCQuality (Aproda ALDC)"). |
| **B14** | **FAIL (blocker)** | `.external\bcquality` **is** a Junction (correct type) but `.Target` = `c:\_EphemeralWorkspace\BCQuality-Aproda` — **not** `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` as required. See *Findings* — this is a freshly-cloned duplicate, not the verified clone. |
| **B15** | **PASS-with-defect** | `BCQUALITY_HOME` **is** now Global (`terminal.integrated.env.windows` in user `settings.json`) — location mechanism correct — but its value is the same wrong/stray clone path as B14. |
| **B16** | **PASS-with-defect** | Re-ran status: reports a verified clone, names the rung (now: VS Code setting `aprodaAldc.bcquality.path`), shows the junction present — all literally true, but the "verified" clone is the wrong one. |
| **B17** | **PASS-with-defect** | Status bar switched to active (`✓ BCQuality`) and reflects state — but the state is wrong. |
| B18 | PASS | Full 4-link chain resolved through the junction: `skills/entry.md` → `skills/read.md` → `skills/do.md` → `microsoft/knowledge/performance/use-setloadfields-for-partial-records.md` — real content each hop. |
| B19 | PASS | `#bcquality` `{operation:"read", path:"skills/entry.md"}` and `{operation:"list", path:"skills"}` both returned real content/listing. |
| B20 | PASS | `#bcquality` rejected `../../../../Windows/win.ini` (`"Path escapes the BCQuality clone root."`) and the absolute path `C:\Windows\win.ini` (`"Path must be relative to the BCQuality clone root, not absolute."`) — no content leaked either way. |
| B21 | PASS | Workspace-wide `grep_search` for `SetLoadFields` → 88 matches / 40 files, all from project sources/docs, **zero** under `.external/bcquality`. |
| B22 | PASS | `@Dredd` run on `Base/SRC/Audit Trail/RoutingEditControl.Codeunit.al`: verdict `PASS_WITH_FINDINGS`, one finding cited to `microsoft/knowledge/style/labels-declared-at-object-scope.md` — I opened that exact file in the clone and confirmed it's real, matching content (not a hallucination). |
| B23 | PASS | Dredd's review completed cleanly, no block/error/loop. |
| B24 | PASS | After setting `external.bcquality.enabled: false` + reconcile: `.external\bcquality` junction gone. |
| B25 | PASS | Reference clone fingerprint unchanged before/after disable: 439 files, `use-setloadfields-for-partial-records.md` SHA256 = `68817735…94D4C` both times. |
| B26 | PASS | `.external\README.md` still present (only the junction was removed). |
| B27 | PASS | Status bar (`⊘ BCQuality`) and quick-pick (*"BCQuality is disabled for this project (external.bcquality.enabled: false)"*) both correctly report disabled — and this correctly overrides even the leaked, still-verifying `aprodaAldc.bcquality.path` rung underneath it. |
| B28 | PASS | Re-enabled (`auto`) + reconcile: junction re-created (`LinkType: Junction`, correct-per-B14-caveat target), re-verified via a successful `#bcquality read`. |
| **B29** | **PARTIAL / NOT fully verified** | No second `.bak` appeared (timestamp unchanged) — consistent with an idempotent "nothing to migrate" run. Could **not** verify byte-identical or capture the literal "Init 5: …" message text — evidence gap on my part (I did not bracket this specific run with an immediate before/after hash of the workspace file; earlier hash drift is more plausibly explained by Phase 5's two `Install/Update BCQuality` invocations touching the file than by non-idempotency of Apply Toolkit itself, but I cannot prove either way). |
| B30 | PASS | Fork `package.json` still `0.1.7`, no `.vsix` tracked, re-confirmed after all phases. |

## What actually happened

Phase 0–2 were clean: the project's pre-Block-4 layout was exactly as expected, the correct build (`0.1.8-test.2`) was active, and the new commands/tool were present and worked correctly *before* the layer arrived — `Show BCQuality Status` and the status bar both correctly resolved BCQuality via the still-existing sibling workspace-folder mount, with every resolver rung individually verdicted.

Phase 3 (`Apply Toolkit`, run by the maintainer) migrated the project layout flawlessly: `.github/aldc.yaml` appeared with the right `toolkitRoot`, the root `aldc.yaml` was removed, the workspace-file backup matched the pre-migration state byte-for-byte, `BCQUALITY_HOME` was fully removed from the workspace file, the new docs arrived, and the legacy sibling-root excludes were replaced by the new `bcquality/**` pattern.

Then, running `Install / Update BCQuality` (the junction-creation step) surfaced the run's one real defect: instead of reusing the clone that `Show BCQuality Status` had *just* verified via the "Mounted workspace folder" rung, it fell through to the `<devRoot>/BCQuality-Aproda` convention candidate — which did not exist — and **silently performed a fresh `git clone`** there (a real `.git`, 439 files, created at the moment of that command). It then junctioned `.external/bcquality` to *that* new clone, and — worse — wrote a **Global** (machine-wide) VS Code setting `aprodaAldc.bcquality.path` pointing at it, which now outranks every other resolver rung. Per your instruction, the rest of the run treated this stray clone as the reference for the remaining phases rather than pausing.

Phase 4 showed that, despite consuming the wrong clone, every actual **consumption mechanism** worked correctly: the four-link chain resolved, the `#bcquality` tool's `read`/`list` worked and correctly rejected path traversal and absolute paths, search hygiene was clean, and a real `@Dredd` review produced a genuine, non-hallucinated citation. This propagation also proved the leaked global setting affects *agent* behaviour, not just the status UI — `@Dredd` itself reported `resolvedFrom: "setting"` pointing at the stray clone.

Phase 5's disable/re-enable cycle worked correctly and safely in both directions: disabling removed only the junction (never touched either clone), correctly overrode the leaked setting to show "disabled", and re-enabling correctly recreated the junction.

Phase 6's second `Apply Toolkit` run produced two await-stops (the target-repo quick-pick again, plus a new warning that the fork sits on `feature/e006-bcquality` rather than `aproda` — expected and correctly surfaced, not a defect) and completed. No second backup file appeared. I could not, however, bracket that specific run with hash captures precise enough to prove strict byte-identical idempotency — a gap in my own evidence-gathering, not a claimed pass.

## Findings

- **Blocker** — `Install / Update BCQuality`'s clone/junction resolution does not reuse the higher-precedence, already-verified "Mounted workspace folder" candidate that `Show BCQuality Status` reports. Instead it falls through to the `<devRoot>/BCQuality-Aproda` convention candidate; when that path is missing, it **silently clones a fresh, independent copy of BCQuality** there rather than erroring, warning, or falling back to the already-verified candidate. Root enabler: `aprodaAldc.devRoot` = `c:\_EphemeralWorkspace` is stale (missing the `Florian Köll` path segment used everywhere else on this machine), but the deeper bug is that the write path's precedence disagrees with the read path's precedence at all — a correct devRoot value would have masked this today, but the underlying inconsistency would resurface differently on another machine.
- **Blocker (compounding)** — the same command writes an **undocumented, Global (machine-wide) VS Code setting** `aprodaAldc.bcquality.path`, not mentioned anywhere in the B14/B15/B16 criteria (which only anticipate `BCQUALITY_HOME` as the Global side effect). Once written, it outranks every other resolver rung, for *every* Aproda project subsequently opened on the machine — not just this one. Confirmed via `@Dredd` that this leak reaches agent tool consumption too.
- **Minor** — the status quick-pick shows two differently-worded "mounted workspace folder(s)" rungs (singular ✓, plural ⊘) with opposite verdicts adjacent to each other; functionally plausible (one checks the specific declared mount, the other scans all mounted roots generically) but the side-by-side wording reads as contradictory and is worth a UI clarification pass.
- **Minor** — `pinnedCommit: ""` in `aldc.yaml` means every BCQuality consultation (including this run's) is against unpinned/live HEAD, a reproducibility gap. `@Dredd` independently flagged the same thing during its review.
- **Nit** — Fork's working tree had pre-existing uncommitted changes unrelated to version/vsix (several `.ts` sources, docs, a leftover Run-1 result file) — not caused by this run, but the maintainer should be aware before relying on "clean tree" assumptions for release packaging.
- **Passed but felt wrong** — B14/B15/B16/B17 all pass their *literal* wording (junction exists, is a Junction, Global setting exists, status reports "verified", status bar reflects state) purely because none of those criteria happened to assert *which* clone. A stricter phrasing (checking the target path, not just its existence) would have caught this immediately — worth tightening the acceptance criteria themselves for the next validation pass.

## Open questions

- Is `aprodaAldc.devRoot` genuinely user-machine-specific and expected to sometimes be wrong (in which case the resolver's fallback-clone behaviour is the real bug to fix), or is `c:\_EphemeralWorkspace` actually supposed to auto-derive the `Florian Köll` segment from something else the extension already has access to?
- Should `Install / Update BCQuality` ever be allowed to silently `git clone` a *new* copy of BCQuality without at least a confirmation prompt, given it can now create divergent, un-synced clones and a persistent Global setting as a side effect?
- Given the Global-setting leak, should the maintainer manually clear `aprodaAldc.bcquality.path` from `%APPDATA%\Code\User\settings.json` now, before it silently affects other Aproda projects opened on this machine?
- For B29: is there an output-channel/log I missed that would have given me the verbatim "Init 5: …" message and let me prove byte-identical idempotency properly, for a future run?
- This run only exercised Run 2 (production order); the "extension first as hard gate vs. recommendation" question depends on Run 1's own result (`e2e-02-RESULT-run1.md` if it exists) which I did not re-verify here.

## Bottom line

**Not ready to release as-is.** The plumbing (migration, junction lifecycle, disable/re-enable safety, the `#bcquality` tool's security boundary, and real end-to-end BCQuality-backed review findings) all work correctly and are a strong positive signal. But the junction/Global-setting resolution defect (B14/B15/B16/B17) is a genuine blocker: it silently creates a duplicate, un-synced BCQuality clone and a machine-wide setting that overrides correct resolution for every project on the developer's machine going forward. That must be fixed before this reaches customer repositories. Whether "extension first" should be a hard release gate rather than a recommendation is a question Run 1's own result should answer together with this one — this run alone shows the production-order path is *mostly* sound but not defect-free.
