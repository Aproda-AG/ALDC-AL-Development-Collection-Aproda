# Assessment of `update-channels-alternatives.md`

> Independent, adversarial check of the alternatives document against the plan, the earlier review, and
> the source. Read-only against every file except this one. Every line below is either **VERIFIED** (I
> read the cited code myself, quoted below) or **SUSPECTED** (inferred / general knowledge, flagged as
> such, same convention the documents under review use).

## Verdict: **MIXED**

The document is careful and mostly correct on the parts it treats adversarially against *itself* —
sections 1, 2 (except 2c), 5 and 6 hold up, and the "simpler design?" answer is honest rather than
performative. But the one recommendation billed as "free" (§2c, the tracked-`.code-workspace` pilot
mechanism) is **backwards**: it is technically accurate about *what* resolves, and wrong about whether
that is good news, in a way that would make the actual failure mode (§3.4's shared machine-wide cache)
worse, not avoided. Section §4 ("contained to one file") is also incomplete — there is a second,
independent hardcoded copy of the cache path the document never found. Both errors matter because they
are exactly the shape of failure the task brief warned about: a plausible mechanism, asserted with real
line citations, that does not survive being followed one file further.

---

## Claim-by-claim verification table

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | `dualVariant` can only do static per-side literal substitution, not a computed value | **Verified** | `$target = $rw.$dstSide` reads a fixed JSON string ([Sync-AprodaLayer.ps1:355](../../tools/aproda-sync/Sync-AprodaLayer.ps1)); the manifest's own rewrite entry is a literal (`"project": "toolkitRoot: \".github\""`, [aproda-sync.json:63-65](../../tools/aproda-sync/aproda-sync.json)). No branch in the rewrite loop shells out or accepts a runtime value. The estimate ("a second *kind* of dual-variant behavior, not one more entry") is fair, not inflated — it is a new conditional path plus one `git rev-parse HEAD` call, which is real but modest work, correctly sized as "understated by §3.3", not "impossible" |
| 2 | `git fetch --tags --prune` without `--force`/`+` means a moved tag stops updating locally, which mechanically kills the moving-tag alternative (§1e) | **Verified (call site) / SUSPECTED (git behavior)** | Call site confirmed verbatim: `await this.git(["fetch", "--tags", "--prune"], this.cachePath, false);` ([layerSource.ts:77](../../tools/aproda-vscode-extension/src/source/layerSource.ts)) — no force flag anywhere in the string. The consequence (git refuses to clobber a local tag pointing elsewhere without `--force`) is standard, well-documented `git-fetch(1)` behavior; the document itself labels this SUSPECTED rather than over-claiming it as read from this repo, which is the correct calibration. The reasoning holds: **this exact call site**, unmodified, is what the rejected alternative would have to rely on, and it would silently fail to track a moved tag |
| 3 | `*.code-workspace` is tracked and in `neverTouch`, so a pilot's channel setting can be committed there — "no new opt-in file needed", a "free pilot mechanism" | **Refuted (on net benefit), Verified (on the literal fact)** | `neverTouch` entry confirmed verbatim: `"*.code-workspace",` at [aproda-sync.json:138](../../tools/aproda-sync/aproda-sync.json). `channel()` reads via `vscode.workspace.getConfiguration(section).get<Channel>("channel", "release")` with **no resource argument** ([config.ts:60-62](../../tools/aproda-vscode-extension/src/config.ts)) — a workspace-level setting in the tracked file's `settings` block genuinely resolves; the mechanical claim is true. **But this is exactly backwards as a pilot mechanism, for a reason the document itself supplies in §3.4 and then doesn't apply here:** a workspace-scope setting in a `.code-workspace` file applies to *every folder in that workspace* to *anyone who opens it* — not to "the 3 designated machines". Combined with §3.4's own finding (managed cache is **one directory per machine**, shared across every project open on it), committing the channel into the tracked file means: (a) any colleague who opens this project on their own, non-pilot machine is silently switched to `branch` with no action of their own — the opposite of "3 machines opt in"; (b) if that machine also has an unrelated `release`-channel project open, its single shared cache gets repointed at the pilot branch the moment the pilot project is opened, contaminating that other project too. A **User-scope** setting, which is what the plan already specifies, requires an explicit, machine-local, deliberate action and cannot leak this way. This is not a "verify precedence works" risk (the document's own stated mitigation) — precedence working *is* the problem. **Confidence: High that this recommendation should not be adopted** |
| 4 | The channel-aware cache path is "a contained, backward-compatible change" because `cachePath` is set once in the constructor | **Partially — real gap found** | Every operational use in `layerSource.ts` (`ensure`, `repair`, `clearCache`, `describe`, `ensureManagedCache`, `cloneManagedCache`) does read the single `this.cachePath` field, confirmed by reading all 23 occurrences in that file — the document's audit of *that file* is accurate and its own use of `resetLocalData` is correct (`layerSource.clearCache()` goes through the field, [resetData.ts:29](../../tools/aproda-vscode-extension/src/commands/resetData.ts)). **What it missed:** `runDoctor` independently reconstructs the same path as a **hardcoded literal**, not through `LayerSource`: `` logger.info(`Managed toolkit cache path: ${path.join(context.globalStorageUri.fsPath, "layer-cache", "fork")}`); `` ([doctor.ts:31](../../tools/aproda-vscode-extension/src/setup/doctor.ts)). If the constructor becomes channel-aware, this line silently keeps reporting the legacy `fork` path — wrong for any non-`release` channel, and wrong specifically in the one command (`Aproda ALDC: Doctor`) a developer would run to diagnose the exact "two projects, two channels, one cache" collision §3.4 describes. The change is real but not "one file" |
| 5 | The missing-`appliedRef` risk "only ever applies to projects switching to `edge`/`branch` for the first time, not to the fleet of 25" | **Verified for the stated case; one untested edge case not raised by either document** | Matches the plan's own §3.2 sentence ("On `edge`/`branch`, `layerVersion` is not consulted for status at all") read the other way, and matches current `check()` structure — today's single-axis version comparison in [service.ts:21-45](../../tools/aproda-vscode-extension/src/version/service.ts) has no channel branch at all yet, confirming the field genuinely does not exist for anyone today. The claim holds for the first-switch case. **Not covered by either document:** a machine moved `release → branch → release → branch` again, or one whose `branch` setting is later repointed to a *different* branch name without a fresh Apply Toolkit run, would carry a **stale** `appliedRef` SHA from an old branch. Per the design this still degrades safely (compared against the *new* branch's `ls-remote` tip, a mismatch just reports `outdated`, never `current` when it shouldn't) — not a defect, but neither document states this explicitly, and it is the natural next question after "does it stay right if a machine is moved and later moved back" |

---

## Which alternatives to adopt, reject, or need more work

**Adopt as written:**
- §1 (keep SHA + `ls-remote`) — the comparison table against manifest/GitHub-API/content-hash/moving-tags
  is honest about costs and does not oversell any rejection. `git describe` as a display-only polish is a
  correctly-scoped, low-priority addition.
- §2 rejections of allow-list, prerelease-tag, and `pinned`-reuse alternatives (2a, 2b, 2d) — all three
  hold up; 2b in particular correctly reuses the review's own B-40-second-instance evidence rather than
  restating it loosely.
- §2e (reducing migration blast radius instead of staging) — correctly separates "good idea generally"
  from "does not remove the need for a pilot now."
- §3's core recommendation (keep `aldc.yaml`, but the D-entry must say the `dualVariant` extension is a
  new capability, not a one-line rewrite) — verified accurate, and the git-ignored-sidecar fallback is a
  reasonable, appropriately-hedged escape hatch.
- §5 (only the cache-path item moves out of E-008's bundle) and §6 (the `unknown`-status rule is right,
  only the motivating scenario is overstated) — both verified against the code as argued.
- The "simpler design?" section's own conclusion (no material simplification of the design shape exists;
  the risk is in implementation, not mechanism) is sound and is not undermined by anything found here.

**Reject:**
- **§2c, the tracked-`.code-workspace` "free pilot mechanism."** See claim 3 above. This is not a minor
  wording issue; adopting it as written in a pilot runbook would produce exactly the failure this epic
  exists to prevent — an update reaching machines nobody deliberately enrolled. If the maintainer wants a
  committed, reviewable record of "who is piloting", that belongs in a document (which §1a of this same
  document already correctly identifies as E-008's job, for a different reason), not in a live,
  auto-applied settings channel.

**Needs more work before it can be adopted:**
- **§4's "contained to the constructor" sizing.** The mechanism itself (make `cachePath` a function of
  `channel()`/`branchName()`) is still sound and still small, but the change set is at minimum two files
  (`layerSource.ts` + `doctor.ts`), and whoever implements it should grep for `"layer-cache"` /
  `globalStorageUri` before calling it contained — the same discipline the plan itself asks for elsewhere
  (Correction 6 in the review: a setting missing from `globalSettingKeys` is exactly this class of miss).
  The scheduling recommendation (fast-follow ticket, not bundled into E-006, not bundled wholesale into
  E-008) still stands independent of this correction.

---

## Errors found in the alternatives document

1. **MAJOR — §2c's "free pilot mechanism" is net harmful, not merely unverified.** The document frames its
   own uncertainty as "does workspace-scope precedence resolve correctly" (a five-minute check). The real
   problem is one level up: *even if precedence resolves exactly as expected*, a workspace-committed
   channel setting is enrolled-by-opening, not enrolled-by-choice, and collides with the same
   machine-wide-cache fact (§3.4) the document itself uses elsewhere. This should have been caught by the
   document's own stated method (follow every consequence one file further) and was not, in the one place
   the task brief specifically asked it to be checked hardest.
2. **MODERATE — §4's "contained to one file" claim is incomplete.** `doctor.ts:31` independently
   hardcodes the same path outside `LayerSource`. Not a large error, but it is the same failure class the
   review caught in the plan itself (Correction 6, a setting missing from `globalSettingKeys`) — a
   secondary read site that would silently go stale — and the alternatives document, whose stated purpose
   is to catch exactly this, missed one instance of it.
3. **MINOR — the confidence framing on §2c is miscalibrated.** "Confidence: Medium — I have not verified
   precedence" understates the issue as a verification gap rather than a design flaw; the fix is not "go
   verify," it is "do not do this."

None of the other sections contain errors of this kind; the document's calibration is otherwise
consistent with its own VERIFIED/SUSPECTED discipline.

---

## Anything both documents missed

- **The `runDoctor` hardcoded cache-path duplicate** (claim 4 above) — missed by the plan, the review, and
  the alternatives document alike. Small, but it is precisely the kind of drift this epic's own history
  (B-29, Correction 6) says to expect and check for explicitly once any code near `cachePath` changes.
- **Branch-repoint without a fresh sync** (claim 5's edge case) — not a defect under the design as
  written, but neither document states the "stale `appliedRef` after switching branch names" behavior is
  intentional-and-safe rather than untested. One sentence would close it.
- **A workspace-committed channel setting doesn't just risk enrolling the wrong machine — it also
  conflicts with §3.6's settings-reset requirement.** `resetGlobalSettings()` only clears
  `ConfigurationTarget.Global` keys ([config.ts:97-99](../../tools/aproda-vscode-extension/src/config.ts));
  a workspace-scope value in a tracked file survives *Reset Toolkit Cache and Settings* untouched by
  construction (the reset was never designed to touch a shared repository file), so a machine that "resets
  everything" would still silently re-enroll in the pilot channel the next time that workspace is opened.
  This is the same class of miss as Correction 6 in the review, and it is a direct consequence of adopting
  §2c that neither this assessment's claim-3 analysis nor the alternatives document itself named
  explicitly until now.

---

## Bottom line for the maintainer

In priority order:

1. **Do not adopt §2c.** Keep the pilot's channel/branch setting at **User** scope, exactly as the plan
   already specifies. Do not commit it to the tracked `.code-workspace` file. If a committed,
   reviewable record of "who is piloting" is wanted, make it a line in a doc (E-008's eventual
   pilot-group-visibility answer), never a live, auto-applied setting.
2. **Fold the `dualVariant`-is-static-only correction into §3.3's D-entry, as the alternatives document
   recommends** — it is correct and the D-entry should say explicitly that this needs a new
   computed-injection capability in `Sync-AprodaLayer.ps1`, with the git-ignored sidecar file named as
   the fallback if that proves riskier than estimated.
3. **If the channel-aware cache path is later built (fast-follow, per §4/§5's otherwise-sound
   recommendation), grep for `"layer-cache"` across the whole extension first** — `doctor.ts` needs the
   same fix or it will silently mislead exactly the diagnostic session it exists to support.
4. **Correct §3.5/§6's scope sentence** as both the alternatives document and this assessment agree: the
   missing-`appliedRef` case is a first-switch condition, not a 25-machine retrofit — worth one sentence,
   not a design change.
5. Everything else in the plan stands as written; nothing found here reopens the SHA-vs-tag decision, the
   `branch`-channel shape, or the `aldc.yaml` storage choice.
