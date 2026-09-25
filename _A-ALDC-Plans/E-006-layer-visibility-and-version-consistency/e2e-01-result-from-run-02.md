# E2E Run 1 — Result: the wrong order (layer without the new extension)

Executed 2026-09-25. Branch `temp/temp-testing-for-aldc` (confirmed, never switched). No commit, no push,
no branch change performed. State left as-is for the maintainer to reset from backup.

> **Deviation from the instructed sequence, disclosed up front:** Phase 1 instructs *one* pull and expects
> the full migration (A5–A9, A14) to be visible after it. In this run, **the first pull did not perform
> the migration at all** — a defect independent of the "wrong order" scenario the run is designed to
> test (see Finding F1). To still obtain the Phase‑2/Phase‑3 evidence the instructions call for, a second
> ("remedial") pull was run, which *did* complete the migration, and a third pull was then run to actually
> exercise the idempotency check that Phase 3 intends. All three pull invocations are reported below with
> their real, unedited output. Nothing in `Sync-AprodaLayer.ps1`, `Initialize-AprodaProject.ps1`, or
> `Migrate-AprodaProjectLayout.ps1` was modified to make anything pass.

One other necessary, disclosed deviation: `Start-Pull.ps1`'s self-location (`$PSScriptRoot`) does not
resolve when the file is invoked via the mandated SRP-safe pattern
(`[ScriptBlock]::Create((Get-Content ... -Raw))`), because that pattern strips `$PSScriptRoot`. The
script itself prints `"...set it manually above"` for exactly this case. `APRODA_SYNC_SCRIPTDIR` was set
to the project's own `.github\tools\aproda-sync` folder (never the fork) directly inside the git-ignored,
machine-local `Start-Pull.ps1` copy — not in `Sync-AprodaLayer.ps1` / `Initialize-AprodaProject.ps1`
themselves.

---

## Result

| ID | Verdict | Note |
|---|---|---|
| A1 | PASS | Branch confirmed `temp/temp-testing-for-aldc`; baseline fully captured |
| A2 | PASS | Root `aldc.yaml` present, `.github/aldc.yaml` absent, `.external/` absent |
| A3 | PASS | `aprodaag.aproda-aldc-0.1.7` confirmed installed |
| A4 | PASS | Pull 1 completed without an unhandled error (only benign `neverTouch` skip warnings) |
| A5 | **FAIL** | `.github/aldc.yaml` did **not** exist after pull 1. Only appeared after a second pull |
| A6 | **FAIL** | Root `aldc.yaml` was **not** removed after pull 1; no `Init 5: [migrated] …` line appeared at all — Init 5 explicitly said it was *skipping* the migration |
| A7 | **FAIL** | `.external/` did not exist after pull 1 (only appeared after pull 2), so "contains a tracked README.md" could not be true either |
| A8 | **FAIL** (as measured after pull 1) | Workspace file after pull 1 had **both** the old `../../BCQuality-Aproda` root and the new `.external` root simultaneously — the old entry was not removed until pull 2 |
| A9 | **FAIL** | The `.bak` file is byte-different from the genuine Phase‑0 baseline (hash `218FDC36…` vs `.bak` hash `F040B2BC…`). It backs up the **pull‑1‑modified** workspace file (which already carries the half-applied `.external` root), not the pristine original — a direct downstream consequence of F1 |
| A10 | **FAIL** (after pull 1) / PASS (after pull 2) | `BCQUALITY_HOME` was still present under `terminal.integrated.env.windows` after pull 1; removed only after pull 2 |
| A11 | PASS (after pull 2) | `search.exclude` and `files.watcherExclude` both carry `"bcquality/**": true`; no `files.exclude` entry targets BCQuality anywhere |
| A12 | PASS (after pull 2) | `.gitignore` block contains `/.github/aldc.yaml`, `/aldc.yaml`, `/.external/bcquality/`, `*.code-workspace.bak` |
| A13 | **PASS** | `.external/bcquality` does not exist at any point across all three pulls — confirms the core prediction that the old extension never creates the junction |
| A14 | **FAIL** | `agents/index.md`, `docs/copilot-reference.md`, `docs/bcquality.md` did **not** arrive in the single first pull (130 files resolved) — they, plus `tools/aproda-sync/Migrate-AprodaProjectLayout.ps1` and `tools/aproda-sync/templates/external-readme.seed.md`, only appeared on the **second** pull (135 files resolved). The T-36 "single pull" fix does not hold in this run |
| A15 | PASS | BCQuality genuinely unreachable through all three rungs (see Phase 2 below) |
| A16 | PASS | `@Dredd` review completed normally — no block, abort, error, or loop |
| A17 | PASS | Dredd recorded `"outcome": "not-applicable"` and expanded to the full native A–G checklist |
| A18 | **Judgement call — visible, not silent.** | Dredd surfaced the BCQuality outcome as the first line under its verdict (`⚪ BCQuality · not mounted — native A–G fallback...`), not buried only in JSON. See quote below |
| A19 | PASS | Confirmed, but only on the **third** pull (`Init 5: project layout already current -- nothing to migrate.`); the second pull was not idempotent, it did the real migration |
| A20 | PASS | Workspace file hash identical before/after the third pull (`00A82E3A…`); no new `.bak` created |
| A21 | PASS | `git status --short` identical before/after the third pull |

---

## What actually happened

**Phase 0.** Baseline captured cleanly: branch correct, root `aldc.yaml` present, `.github/aldc.yaml` /
`.external/` absent, extension `0.1.7` confirmed, workspace file and `.gitignore` block recorded and
hashed (`218FDC36…`).

**Phase 1 — Pull 1 (the instructed single pull).** Ran via
`.github\tools\aproda-sync\Start-Pull.ps1` (after fixing self-location as noted above). Console output:
`Resolved 130 layer file(s)`, one dual-variant (`aldc.yaml (toolkitRoot -> project value)` — note: **not**
yet rewritten to `.github/aldc.yaml`, still same-path). Init step updated the workspace file (added the
`.external` root, added `bcquality/**` to `search.exclude`/`files.watcherExclude`) and the `.gitignore`
block, but then printed, verbatim:

```
Init: templates/external-readme.seed.md not in this project yet -- skipping .external/README.md. Run the pull once more to complete it.
Init 5: Migrate-AprodaProjectLayout.ps1 not in this project yet -- skipping the layout migration. Run the pull once more to complete it.
```

Post-check confirmed: `.github/aldc.yaml` absent, root `aldc.yaml` still present, `.external/` absent,
`Migrate-AprodaProjectLayout.ps1` absent from the project. **The single pull the instructions assume is
sufficient for A5–A9/A14 is not sufficient in practice.**

**Phase 2 — BCQuality reachability + `@Dredd`.** Conducted against the state after Pull 1 (BCQuality
genuinely absent, for the reason above rather than purely "old extension"). Rung 1: no `#bcquality` tool
was found via tool search — consistent with the old extension not contributing it. Rung 2:
`aprodaAldc_readConfiguration` **is** available (old extension) and returned `state: "configured"`,
`bcquality.home: ".external/bcquality"`, `bcquality.enabled: "auto"` — no `resolvedHome`/`verified` fields,
as predicted. Rung 3: `read_file .github/aldc.yaml` failed (file didn't exist yet at that point);
`read_file .external/bcquality/skills/entry.md` failed with "Unable to resolve nonexistent file".

`@Dredd` was invoked on a single small file (`Base/SRC/Audit Trail/ItemEditControl.Codeunit.al`). It
completed normally (`PASS_WITH_FINDINGS`, 3 minor findings, 0 blocker/major), and reported:

> "⚪ **BCQuality · not mounted — native A–G fallback.** BCQuality was **not consulted** in this run
> (`not-applicable` — no clone resolved) → audited natively against the full A–G instruction checklist
> (expanded from the default A/C/F/G because BCQuality is absent)."

This line sits directly under the verdict in the rendered report, not only in the persisted JSON. Dredd
confirmed no retry/loop: a single failed probe of `.external/bcquality/skills/entry.md` was treated as
definitive absence per its own protocol, then it proceeded straight to the native checklist.

**Phase 3 — idempotency.** A second, unmodified pull was run next. It was **not** a no-op: it resolved 135
files (5 more than pull 1 — exactly the ones pull 1 had reported missing) and this time executed the full
migration: root `aldc.yaml` removed, `.github/aldc.yaml` created, `.external/README.md` created, workspace
file rewritten (old sibling root removed, `BCQUALITY_HOME` removed, stale excludes removed), backup
written to `StraubMedicalAGBase.code-workspace.bak`. `.external/bcquality` still did **not** appear —
consistent with the old extension never creating the junction. A third pull was then run to obtain the
idempotency evidence the instructions actually intend: it reported `Init 5: project layout already
current -- nothing to migrate.`, an unchanged workspace-file hash, and no new `.bak`.

**Phase 4.** Final `git status --short`: `M .gitignore`, `M StraubMedicalAGBase.code-workspace`,
`?? .external/`, `?? .github/_e2e-test/`. No commit, revert, or cleanup performed.

---

## Findings

- **F1 — blocker.** The first pull against a genuinely pre-Block-4 project systematically resolves 5 fewer
  files than a second, immediately-following, unmodified pull of the same source against the same
  destination (130 vs 135) — specifically `agents/index.md`, `docs/copilot-reference.md`,
  `docs/bcquality.md`, `tools/aproda-sync/Migrate-AprodaProjectLayout.ps1`, and
  `tools/aproda-sync/templates/external-readme.seed.md`. Because `Migrate-AprodaProjectLayout.ps1` is
  among the missing files, **the entire layout migration (A5–A10, A14) silently fails to run on the first
  pull, in every project, regardless of extension version** — this is not specific to the "wrong order"
  scenario this run was designed to isolate. It directly contradicts the T-36 "single pull" promise
  (A14) and the implicit assumption behind A5–A9 that one pull suffices. Root cause not investigated
  further (out of scope: would require inspecting the fork's resolver, and rule 8 disallows treating that
  as this run's job) — but the symptom is fully reproducible: it happened identically and deterministically
  once in this session, then resolved on the very next unmodified pull.
- **F2 — major, downstream of F1.** Because migration doesn't run in pull 1, `Initialize-AprodaProject.ps1`
  still edits the workspace file in pull 1 (adding the `.external` root, new excludes) *before* the backup
  is ever taken. When `Migrate-AprodaProjectLayout.ps1` finally runs (pull 2), the `.bak` it writes
  captures the **already-modified** file, not the genuine pre-Block-4 original. A9's "byte-identical to
  the true baseline" guarantee cannot hold whenever F1 occurs, which — per F1 — is every first pull.
- **F3 — minor, but worth fixing before this reaches customers.** `Start-Pull.ps1`'s self-location
  (`$PSScriptRoot`) does not resolve under the mandated SRP-safe invocation pattern
  (`[ScriptBlock]::Create((Get-Content ... -Raw))`), only under literal file execution or the PowerShell
  extension's "Run Selection". The script's own fallback message assumes an interactive editor session
  (`psEditor`), which isn't available to an agent invoking it programmatically. This is a usability gap
  for exactly the audience (automation, agents) the SRP-safe pattern exists to serve.
- **F4 — passed, but felt fragile.** A13's PASS ("no junction created by the old extension") is real and
  reproducible, but it is currently indistinguishable, from the project's point of view, from "migration
  never ran at all" (F1). A developer inspecting only `.external/bcquality`'s absence cannot tell those
  two very different failure modes apart without also checking whether `.github/aldc.yaml` exists.
- **F5 — informational, genuinely reassuring.** A15–A18 confirm the implementer's core mechanism works:
  BCQuality absence is detected via a single non-retried probe, does not block/loop the review, falls back
  to the full native checklist, and — contrary to the implementer's own stated worry — **is not silent**.
  `@Dredd`'s report surfaces the degraded state as the first line under its verdict. This is the one part
  of the prediction that measurement contradicts in the *good* direction.

---

## Open questions

1. Is the 130→135 file gap (F1) deterministic across machines/clones, or specific to something about this
   session's fork checkout (e.g., a file-system timestamp/cache state at the moment of the first pull)? I
   did not investigate the resolver internals, per the instruction to test the project, not the toolkit.
   This needs the implementer's own reproduction, ideally from a byte-for-byte fresh fork clone.
2. Given F1, is "run the pull twice" an acceptable *documented* workaround, or does F1 need a real fix
   before release? The briefing's own two-run design (extension-then-layer vs layer-then-extension)
   implicitly assumes a single pull is authoritative; F1 undermines that assumption independently of
   ordering.
3. A18 was answered from a single `@Dredd` invocation. Is "visible in Dredd's report" sufficient evidence
   for the general claim ("agents surface BCQuality absence"), or should the same probe be repeated
   against `@al-developer`'s code-review subagent path, which is the other consumer mentioned in the
   copilot-instructions "Skills Evidencing" section?
4. Phase 2, step 2 ("look at the Explorer, describe what a developer would see") is **NOT-REACHED** — no
   tool available in this session can reload the VS Code window or inspect the Explorer tree. Based on the
   workspace-file evidence alone: after pull 1 the `.external` folder root points at a nonexistent
   directory (would very likely render as a broken/greyed entry); after pull 2/3 it exists but is
   effectively empty (only `README.md`, no `bcquality/` subfolder) — a developer would see an oddly sparse
   folder, not an explanatory message. This is inference, not observation, and should be confirmed by a
   human with an actual editor reload.

---

## The question this run exists for

> If the Block-4 layer were released to the fleet before the new extension, what would actually happen to
> every project on its next pull — and would anyone notice?

**The measured answer contradicts the implementer's prediction, but not in the reassuring direction.**
The implementer predicted "BCQuality goes silently dark" as the sole consequence of wrong ordering. What
was actually measured is worse and is **not specific to ordering at all**: the very first pull any
project performs after Block-4 ships will, per F1, fail to complete the layout migration regardless of
which extension is installed, requiring an undocumented second pull to reach the state the acceptance
criteria assume. Only once that second pull has happened does the "wrong order" story (F4/A13: no
junction, because the old extension doesn't know how to create one) become the operative, visible cause
of BCQuality being unreachable. Whether anyone would notice: **yes, if they read the console output**
(pull 1 prints an explicit `"Run the pull once more to complete it"` line, and — once BCQuality really is
absent — `@Dredd`'s own report visibly says so, per F5). **No, if they only skim for a green exit code**,
since pull 1 still exits without an unhandled error (A4 genuinely passes) and nothing outside the log
text signals that the migration was incomplete.

**Severity: F1 is a blocker for the release-ordering decision this run was meant to inform** — it must be
resolved or at minimum explicitly documented as "always pull twice on first adoption" before "extension
first" can be evaluated as a recommendation vs. a hard gate, because right now *even the production-order
Run 2* will hit the identical first-pull gap for reasons unrelated to extension version.

---

**Stopping here as instructed. Run 2 was not started. The maintainer resets the project from backup
before Run 2 begins.**
