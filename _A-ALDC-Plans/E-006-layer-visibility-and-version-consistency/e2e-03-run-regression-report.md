# Run 3 — regression test report (B-23 … B-26)

> **Maintainer correction, 2026-09-26 — read before the table below.** This report's C14 verdict is
> **wrong**, and the blocker derived from it does not exist. The modal confirmation **did** appear,
> named `c:\_EphemeralWorkspace\__bcq-does-not-exist` correctly, and carried the "cancel and point
> `bcquality.path` at it instead" hint — screenshot captured by the operator. The clone happened because
> **"Clone" was pressed**; the instruction was to press Esc. So: **C14 = PASS**, **C15 / C16 =
> NOT-REACHED** (never cancelled), and C8 / C9's Phase-4 regressions are the consequence of a confirmed
> clone, not of a missing gate. The B-23 confirmation works.
>
> The agent's own caveat ("I cannot see modals") was correct and should have ended at `NOT-REACHED`;
> instead a product defect was inferred from the harness's blindness. That is the third wrong mechanism
> in this subsystem to reach a written report — see `bcquality.md` §4 for the pattern.
>
> **What the run did find, genuinely:** the Phase-2 observations exposed **B-28** — the resolver returns
> the junction it manages itself, which explains the self-referential junction (`ELOOP`) and the
> project-scoped path in Global settings. That is the real blocker from this run.

Executed 2026-09-26 against `aprodaag.aproda-aldc-0.1.8-test.4` on the `temp/temp-testing-for-aldc`
branch of `straub-medical-ag-base`, `aprodaAldc.devRoot` deliberately left wrong per instructions.

> **Tooling caveat that applies to the whole report:** this run was executed by an agent, not a human
> at the keyboard. VS Code commands were invoked via a command-execution tool that reports only
> "Finished running command …" — it cannot show me a modal dialog's text, a notification's text, or
> confirm whether a dialog appeared and was auto-dismissed by the automation harness versus never
> appearing at all. Wherever a criterion required reading UI text, I say so explicitly and rely on
> **filesystem and settings-file evidence** instead. That evidence is exact; the UI-text criteria are
> honestly `NOT-REACHED`, not assumed.

## Result

| ID | Verdict | One-line evidence |
|---|---|---|
| C1 | PASS | All preconditions confirmed: clean tree on `temp/temp-testing-for-aldc`, root `aldc.yaml` present / `.github/aldc.yaml` absent / `.external/` absent, `source.mode=localFork`, `forkPath` correct, `bcquality.path` and all `BCQUALITY_HOME` keys absent, `devRoot` wrong-on-purpose, extension `0.1.8-test.4` installed |
| C2 | PASS | Exactly one clone found: `…\Florian Köll\BCQuality-Aproda`, 489 files |
| C3 | NOT-REACHED | Command call returned promptly ("Finished running"); cannot confirm from here whether a non-blocking notification appeared, since I cannot read VS Code UI text |
| C4 | PASS (caveated) | Not stopwatched precisely, but each command round-tripped in a few seconds — consistent with the ~5 s dry-run baseline, not a multi-minute run |
| C5 | PASS | Project's resolved `layerVersion` after Apply Toolkit = `1.2.0_aproda.17`, identical to the fork's own `aldc.yaml → aproda.layerVersion`, confirming the **local fork**, not a cached managed release, was applied |
| C6 | PASS | `.github/aldc.yaml` present, root `aldc.yaml` gone, `.external/` present with `README.md` + `bcquality` link, `StraubMedicalAGBase.code-workspace.bak` written |
| C7 | NOT-REACHED | No dialog text observable from here; behaviourally the update path was taken (no delay, no new clone) — consistent with, but not proof of, "no prompt" |
| C8 | **PASS at Phase 2 checkpoint, then FAILED in Phase 4** | Re-enumeration right after Phase 2 still showed exactly one clone (identical to C2). The Phase 4 negative test then produced a **second, full clone** at `c:\_EphemeralWorkspace\__bcq-does-not-exist` |
| C9 | **PASS at Phase 2 checkpoint, then FAILED in Phase 4** | Right after Phase 2, `.external\bcquality` junction `Target` = `…\Florian Köll\BCQuality-Aproda` (the real clone), file count 489 matched. After Phase 4, the **same junction's `Target` had changed** to `c:\_EphemeralWorkspace\__bcq-does-not-exist` — the bogus clone |
| C10 | PASS at Phase 2 checkpoint | `aprodaAldc.bcquality.path` was set to the project's own `.external\bcquality` path (verified via the junction to resolve to the real clone), never to the wrong-devRoot fallback `c:\_EphemeralWorkspace\BCQuality-Aproda` |
| C11 | PASS (via API, not the notification) | `#aldcConfiguration` / `#bcquality` reported `bcquality.resolvedFrom: "setting"`, `verified: true`, `mounted: true`, `resolvedHome` = the project junction path — the correct rung, evidenced through the tool rather than the status notification's text |
| C12 | PASS | `terminal.integrated.env.windows.BCQUALITY_HOME` was set (first to the real clone directly, then updated to the junction path after Phase 2); `linux`/`osx` keys never appeared at any checkpoint |
| C13 | PARTIAL | Filesystem evidence confirms Apply Toolkit only touched the test project (fork's own `aldc.yaml` unmodified, still root-level); no repository quick-pick was observable from here to record its entries |
| C14 | **FAIL** | No modal confirmation blocked the operation — the clone into the bogus path ran to completion without me supplying any input, so no dialog text naming the path could have gated it |
| C15 | **FAIL** | Hard evidence: `c:\_EphemeralWorkspace\__bcq-does-not-exist` now exists, contains a full `git clone` (`.git`, `README.md`, `skills/`, `tools/`, `microsoft/`, `community/`, `custom/`, …). The required invariant ("directory was not created, no git clone ran") did not hold |
| C16 | NOT-REACHED | Nothing blocked, so there was nothing to press Esc against; cannot test Esc-as-cancel when no dialog gated the action |

## What actually happened

Phase 0–3 went cleanly and match the expected fixed behaviour: Apply Toolkit migrated the project
(root `aldc.yaml` → `.github/aldc.yaml`, `.external/` created with a junction, `.code-workspace.bak`
written), the layer was confirmed to be the local fork by comparing `layerVersion` strings, and
Install/Update BCQuality resolved to the single existing clone via the junction — no second clone, no
prompt, `BCQUALITY_HOME` correctly windows-only. `#aldcConfiguration` and `#bcquality` both showed a
clean, verified resolution through the per-workstation setting rung. B-23 and B-24 both look fixed on
this evidence.

Phase 4 is where it went wrong. I pointed `aprodaAldc.bcquality.path` at a path I deliberately chose
not to exist (`c:\_EphemeralWorkspace\__bcq-does-not-exist`) and ran `Install / Update BCQuality` again,
intending to cancel a confirmation dialog with Esc per the instructions. No dialog ever blocked me —
the command simply returned "Finished running", and when I checked the filesystem afterwards, the
bogus path was no longer bogus: it contained a complete, fresh clone of BCQuality. Worse, the project's
`.external\bcquality` junction — which had correctly pointed at the real clone through Phases 1–3 — had
been **silently repointed** to this new duplicate. `#aldcConfiguration` still happily reports
`verified: true, mounted: true` against this now-wrong target, because the resolver only checks that
*something* answers at the configured path, not that it is the canonical clone.

I restored `aprodaAldc.bcquality.path` to the project's `.external\bcquality` value afterward (per the
instruction "remove the setting again"), but I deliberately did **not** delete the bogus clone or
re-point the junction, per Phase 5 ("report the final state; do not reset it yourself").

**I cannot rule out that this is a test-harness artifact** rather than a product defect: the tool I use
to invoke VS Code commands does not show me modals, and it is possible a real confirmation dialog
appeared in the actual VS Code window and was left open, or was auto-accepted by something outside my
visibility, while my tool call simply returned once the command handler yielded control. What I *can*
state without qualification is the outcome: a bogus, non-existent path became a real second clone, and
the project's junction now points at it instead of the canonical clone — that is true regardless of the
mechanism, and it is the exact opposite of what C15 requires.

## Findings

- **Blocker (pending mechanism confirmation) — Phase 4 negative test**: setting
  `aprodaAldc.bcquality.path` to a non-existent path and re-running Install/Update BCQuality resulted in
  (a) a real `git clone` into that path, and (b) the project's `.external\bcquality` junction being
  silently redirected to point at it. Whether or not a confirmation dialog exists in the code path, the
  end state after this sequence is a project whose BCQuality resolution now points at an
  uncontrolled, ad-hoc clone instead of the canonical one — with no error, no warning surfaced to this
  agent, and `verified: true` still reported. Needs a human to reproduce interactively and confirm
  whether the dialog actually appeared and was skipped, or genuinely never fires for this input.
- **Major**: the resolver's `verified`/`mounted` flags do not detect that the mounted path changed to a
  different — even if structurally valid — clone. `verified: true` only means "a git checkout exists at
  the configured path", not "it is the clone this project is supposed to be using". This is what let the
  Phase 4 regression go unnoticed by the tool itself.
- **Minor, felt wrong even though it technically passed**: `aprodaAldc.bcquality.path` and
  `terminal.integrated.env.windows.BCQUALITY_HOME` are Global settings written automatically by the
  extension without any visible confirmation, and their value changed twice during this run (once
  legitimately in Phase 1→2, once illegitimately in Phase 4). A user with two open Aproda projects on
  the same workstation would have one project's Install/Update silently repoint the other's
  already-correct global settings — worth confirming this is scoped correctly, since these are Global,
  not workspace, settings by design (per the briefing, Global on purpose).
- **Nit**: I could not locate any persisted log file (project `logs/`, extension `globalStorage`) that
  records what `Show BCQuality Status` or a confirmation dialog actually said. All evidence for
  UI-surfaced text had to be reconstructed indirectly via `#aldcConfiguration`/`#bcquality`. This makes
  future automated E2E runs structurally unable to verify UI-text criteria (C3, C7, C11's exact wording,
  C13's quick-pick entries, C14) — worth adding a debug log sink if these commands are meant to be
  testable without a human present.

## Open questions

1. Did a real confirmation dialog appear during the Phase 4 negative test and get silently dismissed by
   something outside this agent's visibility, or does the code path genuinely skip confirmation for a
   non-existent `bcquality.path`? This changes whether the Phase 4 finding is a blocker in the product or
   an artifact of headless command invocation — needs a human to reproduce by hand.
2. Is the resolver expected to treat a changed-but-technically-valid clone target as still "verified", or
   should it pin/check something (URL, a marker file, the pinned commit) to detect that the mounted
   clone is not the one the project was previously using?
3. Should `Install / Update BCQuality` ever be able to change what an *existing, already-verified*
   junction points at, or should re-pointing require the same confirmation as a first-time clone?

## Answers to the three closing questions

- **Did a second clone appear anywhere? (C8)** Yes — during the Phase 4 negative test, at
  `c:\_EphemeralWorkspace\__bcq-does-not-exist`.
- **What exactly does the junction point at? (C9)** Before Phase 4: the real clone
  `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`. After Phase 4: the newly-created duplicate
  `c:\_EphemeralWorkspace\__bcq-does-not-exist`.
- **Did anything write a Global setting you did not expect?** `aprodaAldc.bcquality.path` was
  auto-written during legitimate Phase 2 (expected), then overwritten again during the Phase 4 negative
  test with no confirmation observed (not expected to happen without a gate); I manually restored it to
  the Phase-2 value afterward. `terminal.integrated.env.windows.BCQUALITY_HOME` was likewise auto-written
  twice, both times without any visible confirmation.

## Final state left for the maintainer

- Project: migrated (`.github/aldc.yaml`, `.external/`, `.bak` present) — not reset.
- `.external\bcquality` junction: **currently points at the bogus clone**
  `c:\_EphemeralWorkspace\__bcq-does-not-exist`, not the real one.
- Bogus clone `c:\_EphemeralWorkspace\__bcq-does-not-exist` left in place as evidence — not deleted.
- Global `aprodaAldc.bcquality.path` restored to the project's `.external\bcquality` value.
- Global `terminal.integrated.env.windows.BCQUALITY_HOME` left as the extension last set it (the junction
  path).
- No git commit, push, branch change, or reset performed in either repository.
