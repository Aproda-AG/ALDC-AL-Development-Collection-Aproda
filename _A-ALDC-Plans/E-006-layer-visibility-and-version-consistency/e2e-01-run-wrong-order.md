# Run 1 — the wrong order: layer without the new extension

> **Read [`e2e-00-briefing.md`](e2e-00-briefing.md) first.** It holds the environment facts and the hard
> rules. This file only contains the steps.
>
> **This run is expected to leave the project degraded. That is the result, not a failure of the run.**
> Do not repair anything mid-run. Do not install the new extension.

**Purpose.** Measure what actually happens when the Block-4 layer reaches a project *before* the new
Aproda VS Code extension does. The implementer predicted that BCQuality goes silently dark. This run
decides whether that prediction is right, and how visible the degradation is to a developer — which in
turn decides whether "extension first" is a recommendation or a hard release gate.

**Installed extension must stay `aprodaag.aproda-aldc` 0.1.7 for the whole run. Do not build, package,
install or reload anything extension-related.**

---

## Phase 0 — Baseline

Record the starting state. You will compare against it later, so capture it, do not summarise it.

1. In the test project: `git status --short`, `git branch --show-current`. Confirm the branch is
   `temp/temp-testing-for-aldc`. If it is anything else, **stop and report**.
2. Record which of these exist: `aldc.yaml`, `.github/aldc.yaml`, `.external/`,
   `.external/README.md`, `StraubMedicalAGBase.code-workspace`, `*.code-workspace.bak`.
3. Copy the full contents of `StraubMedicalAGBase.code-workspace` into your report (it is short). Note
   specifically: the `folders` array, and whether `settings` contains `BCQUALITY_HOME` anywhere under
   `terminal.integrated.env.*`.
4. Record the `# Aproda ALDC Tool - BEGIN/END` block from the project's `.gitignore`.
5. Confirm the installed extension version:
   `Get-ChildItem "$env:USERPROFILE\.vscode\extensions" -Directory -Filter 'aprodaag.aproda-aldc*' | Select-Object -ExpandProperty Name`

| ID | Criterion |
|---|---|
| **A1** | Branch is `temp/temp-testing-for-aldc` and the baseline is fully captured |
| **A2** | Starting layout is the pre-Block-4 one: root `aldc.yaml` present, `.github/aldc.yaml` absent, `.external/` absent |
| **A3** | Installed extension is `0.1.7` (the old build) |

---

## Phase 1 — Run the real pull

Use the project's own machine-local entry point — this is the routine path a developer actually runs,
which is what makes the result meaningful.

```powershell
$proj = "c:\_EphemeralWorkspace\Florian Köll\_GitHub\straub-medical-ag-base"
& ([ScriptBlock]::Create((Get-Content "$proj\.github\tools\aproda-sync\Start-Pull.ps1" -Raw)))
```

Capture the **complete** console output — it is the primary evidence for this phase. Pay attention to
lines beginning `Dual-variant:`, `Init:` and `Init 5:`.

| ID | Criterion |
|---|---|
| **A4** | The pull completes without an unhandled error |
| **A5** | `.github/aldc.yaml` now exists and contains `toolkitRoot: ".github"` |
| **A6** | The root `aldc.yaml` is **gone**, and the output explains why (`Init 5: [migrated] Removed stale root aldc.yaml …`) |
| **A7** | `.external/` exists and contains a tracked `README.md` |
| **A8** | The workspace file's BCQuality root is now `.external` — the `../BCQuality-Aproda` entry is gone |
| **A9** | `StraubMedicalAGBase.code-workspace.bak` was created, and its content is byte-identical to the baseline you captured in Phase 0 |
| **A10** | `BCQUALITY_HOME` no longer appears anywhere in the workspace file |
| **A11** | The workspace `settings` now carry `search.exclude` **and** `files.watcherExclude` on `bcquality/**`, and **no** `files.exclude` entry targeting BCQuality |
| **A12** | The `.gitignore` Aproda block now contains `/.github/aldc.yaml`, `/aldc.yaml`, `/.external/bcquality/` and `*.code-workspace.bak` |
| **A13** | **`.external/bcquality` does NOT exist** — no junction was created, because the old extension does not know about it |
| **A14** | `agents/index.md`, `docs/copilot-reference.md` and `docs/bcquality.md` arrived under `.github/` **in this single pull** (this is the T-36 fix; before it they needed a second pull) |

For **A9**, compare with a hash, not by eye.

---

## Phase 2 — The actual question: what does a developer experience now?

This is the part that produces the new information. Take it seriously; it is not a formality.

1. **Reload the VS Code window** so the workspace file is re-read.
2. Look at the Explorer. Is there a BCQuality root? What does it look like — empty, yellow, missing,
   normal? **Describe what a developer would actually see**, not what the config says.
3. Try to read the knowledge base the way an agent would, using the documented three-rung path:
   - Rung 1: is a `#bcquality` tool available at all? (It should not be — the old extension does not
     contribute it.) Record how its absence manifests.
   - Rung 2: is `#aldcConfiguration` available? If yes, what does it return for `home`,
     and does it return `resolvedHome` / `verified`? (The old tool does not know those fields.)
   - Rung 3: `read_file .github/aldc.yaml` — does it work? What is the declared `home`? Then attempt
     `read_file <home>/skills/entry.md`, i.e. `.external/bcquality/skills/entry.md`. Record the exact
     failure.
4. **Run a real review.** Invoke `@Dredd` on a small, real scope in this project (a single changed
   object, or one small module — keep it cheap). Then read its output and answer:
   - What did it record for BCQuality — `disabled`, `not-applicable`, `active`, or something else?
   - Did it **block, error, retry, or loop**? (It must not. `fallback.neverBlock: true`.)
   - Did it fall back to the full native A–G checklist, as the contract promises?
   - **Was the degradation visible in its output at all**, or would a developer have read the report
     and assumed BCQuality had been consulted?

| ID | Criterion |
|---|---|
| **A15** | BCQuality is genuinely unreachable — the entry point cannot be read through any of the three rungs |
| **A16** | The review completes and does **not** block, abort, error or loop |
| **A17** | The review records a BCQuality outcome of `not-applicable` (or `disabled`), and falls back to the full native checklist |
| **A18** | **Judgement call — answer explicitly:** is the degradation *visible* to a developer reading the output, or is it silent? Quote the relevant lines. |

**A18 is the most valuable line in this run.** If the answer is "silent", that is a finding in its own
right, independent of the release ordering.

---

## Phase 3 — Idempotency under the degraded state

Run the pull a **second** time, unchanged.

| ID | Criterion |
|---|---|
| **A19** | The second pull reports `Init 5: project layout already current -- nothing to migrate.` |
| **A20** | The workspace file is **byte-identical** to after the first pull (hash it), and no second `.bak` was created |
| **A21** | Nothing new appears in `git status --short` compared with after the first pull |

---

## Phase 4 — Record, then stop

1. Run `git status --short` and `git diff --stat` in the test project and record them. **Do not commit,
   do not revert, do not clean up.** The maintainer resets from the backup.
2. Write your report per the contract in the briefing.

Then explicitly answer, in your own words, the question this run exists for:

> **If the Block-4 layer were released to the fleet before the new extension, what would actually happen
> to every project on its next pull — and would anyone notice?**

State it as a finding with a severity. If your measurement contradicts the implementer's prediction
(that BCQuality goes silently dark), say so plainly — that is a more valuable outcome than confirming it.

**Stop here.** Do not proceed to Run 2. The maintainer resets the project first.
