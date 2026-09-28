# Design alternatives — `update-channels.md`

> Read-only review against the plan as of 2026-09-28 (post-review, post-maintainer-proposal). Nothing
> implemented. Every claim below is checked against the current source; **VERIFIED** means I read the
> cited line(s) myself, **SUSPECTED** means it is inferred/general knowledge not directly checkable in
> this repository.

## Summary

| # | Decision | Plan's choice | My call | Confidence |
|---|---|---|---|---|
| 1 | Detection mechanism for moving refs | Commit SHA via `git ls-remote refs/heads/<branch>` | **Keep.** Every alternative (manifest file, GitHub API, content hash, moving tags, `git describe`) costs more for the same or less signal | High |
| 2 | Pilot shape | New `branch` channel + configurable branch name | **Keep the channel; add one thing the plan missed for free** — the existing tracked `*.code-workspace` already lets a pilot's `channel`/`branch` setting be committed and code-reviewed per project. No new "opt-in file" needed | High on rejecting the alternatives; Medium on the free addition |
| 3 | Storage for the applied ref | `aldc.yaml`, written by the syncer | **Keep**, but flag that the `dualVariant` mechanism as it exists today (static per-side string substitution) cannot do this — it needs a new, computed-value class of dual-variant, which is more work than §3.3 implies | Medium |
| 4 | One-channel-per-machine constraint | Accept it, defer the fix to E-008 | **Split it.** The channel-aware cache path is a small, contained, backward-compatible change confined to one file — cheap enough to build as an immediate fast-follow, but *not* worth pulling into this release given the plan's own scope-creep history | Medium |
| 5 | Scope line vs. E-008 | Rollout policy, pilot UI, cache path all deferred together | Keep policy/UI deferred; **separate the cache-path item** into its own fast-follow ticket rather than bundling it with genuine policy work | Medium |
| 6 | Missing-field rule (25 projects) | New `unknown` status, resolved by next apply | **Keep the rule, narrow the scope statement.** The field is only ever consulted on `edge`/`branch`; all 25 production machines are on `release`, so today the "missing field" case cannot occur for any of them — it is a first-run condition for whoever switches, not a retrofit problem for the fleet | High |

---

## 1. Is SHA-based detection the right mechanism?

**The plan's choice:** `git ls-remote <repo> refs/heads/<branch>` for the remote tip; the syncer writes
the checked-out commit SHA into `aldc.yaml`.

### Alternatives considered

**a) A published manifest file** (JSON in the repo or a release asset) describing what each channel
currently points at.

- *Buys:* one document readable by a human ("edge is at `abc1234`, as of commit `<msg>`"); could later
  double as E-008's "who is on what" answer.
- *Costs:* something has to **write** it on every push to a moving branch — either a new CI workflow
  (more infrastructure, and D-23's whole CI gate exists specifically for `release`; extending CI to
  fire on every push to a feature branch is real new surface) or a manual step (exactly the class of
  forgettable action B-6/B-38 exist to catch). It also duplicates information `ls-remote` already gives
  for free, with zero publishing step. **Reject for E-006** — it is solving a problem `ls-remote`
  already solves, at the cost of a new artifact and a new place for drift (the manifest itself going
  stale is now a sixth failure mode). Worth remembering for E-008's pilot-group visibility question,
  where the *audience* problem (not the *version* problem) genuinely needs a document.

**b) GitHub API instead of `ls-remote`.**

- *Buys:* richer metadata (author, message, timestamp) for a nicer notification.
- *Costs:* a second authentication path. [`service.ts:64-69`](../../tools/aproda-vscode-extension/src/version/service.ts)
  and [`layerSource.ts` clone flow](../../tools/aproda-vscode-extension/src/source/layerSource.ts) already
  rely on the machine's git credential store (with an explicit terminal-based fallback for
  interactive auth in `cloneManagedCache`); a REST call needs its own token/PAT setting, its own rate
  limit handling, and a new settings key with the exact "forgot to add it to `globalSettingKeys`" risk
  **B-39's own review already flagged for the `branch` setting** ([Correction 6](update-channels-review.md)).
  No functional gain over `ls-remote`, which already returns the one thing that is actually needed (a
  SHA). **Reject.**

**c) A content hash of the delivered layer instead of a commit SHA.**

- *Buys:* would catch two different commits producing byte-identical trees (rare, and not a scenario
  either B-39 or B-40 names).
- *Costs:* `ls-remote` returns refs, not trees — computing a remote content hash without cloning is not
  possible with the tools already in use here; it would need the GitHub API's tree endpoint (dragging
  in alternative (b)'s costs) or a full fetch on every check (defeating the "no clone" property the
  review explicitly praised: *"`ls-remote` reads the remote tip without touching the cache"*). **Reject**
  — no known failure mode needs it, and it reintroduces the network cost the SHA approach was chosen to
  avoid.

**d) `git describe` instead of a raw SHA.**

- *Buys:* a friendlier label (`v1.2.0_aproda.9-3-gabc1234`) instead of a bare hash in
  `"Aproda ALDC update available: ${installed} -> ${available}"` ([service.ts:39](../../tools/aproda-vscode-extension/src/version/service.ts))
  — the plan's message template is inherited unmodified for the SHA case and would otherwise show raw
  hashes to a human.
- *Costs:* `git describe` needs a real working tree with tag ancestry — it can describe the **installed**
  side (the managed cache, which is a genuine clone) but cannot describe the **remote** tip without
  cloning first, so it is not a substitute for `ls-remote` on the availability side. It also depends on
  annotated/lightweight tags existing in the branch's ancestry, which is true today but is one more
  assumption to keep true.
- **Verdict:** not a replacement for the detection mechanism, but a legitimate, low-priority *display*
  polish for the "installed" half of the message once a SHA is in play. Worth one line in
  implementation notes, not worth its own design section.

**e) Lightweight/annotated tags on a side branch, moved to the tip on every push, then compared exactly
like `release` (reusing `compareLayerVersions`/tag-list code unchanged).**

- *Buys:* zero new comparison code path in `VersionService` — `edge`/`branch` would look exactly like
  `release` to the code, just against a different tag prefix.
- *Costs, and this is the one that actually kills it:* a *moved* tag requires `git fetch` with an
  explicit `+`/`--force` refspec for tags, because git's default tag-fetch behavior refuses to
  clobber an existing local tag that already points somewhere else (**SUSPECTED** — general git
  behavior, not independently checkable in this repository, but well-documented in `git-fetch(1)`).
  The existing fetch call is `await this.git(["fetch", "--tags", "--prune"], this.cachePath, false);`
  ([layerSource.ts:78](../../tools/aproda-vscode-extension/src/source/layerSource.ts)) — no force flag.
  A moving tag would silently stop updating locally the first time it moved, and the failure would look
  exactly like B-39/B-6: a check reporting "current" when it is not. Building a moving-tag mechanism
  correctly would mean auditing and probably changing that fetch call, plus accepting that a moving tag
  is itself a git anti-pattern most tooling (including this extension's own `compareLayerTags` sort at
  [layerSource.ts:225](../../tools/aproda-vscode-extension/src/source/layerSource.ts)) does not expect.
  **Reject** — SHA-over-branch-ref sidesteps this entire class of problem by construction, which is
  exactly what the review already concluded for the tag-vs-SHA question in general; this is the specific
  mechanical reason the conclusion holds.

### Recommendation

**Keep SHA + `ls-remote`.** Every alternative either reproduces the same information at a real
infrastructure cost (manifest, GitHub API) or trades the "no clone" property for a marginal or
non-existent benefit (content hash, moving tags). `git describe` is worth one line for display purposes
only. **Confidence: High** — this is the one decision in the plan I would not touch.

---

## 2. Is a new `branch` channel the right shape for the pilot?

**The plan's choice:** a fourth channel value, `branch`, with a companion branch-name setting.

### Alternatives considered

**a) An allow-list of machines**, read from somewhere central, gating who gets what.

- *Buys:* the most direct answer to "give it to 3 of 25."
- *Costs:* requires a machine-identity concept that does not exist anywhere in this codebase today — no
  telemetry, no machine ID, no registry. It also needs a place to *read* the list from, which is either
  the manifest-file idea (rejected in §1a for its own reasons, now needed for an unrelated purpose) or a
  new backend service. This is not a cheaper version of `branch` — it is E-008's entire pilot-group-management
  scope, which the plan and E-008 both correctly keep out of this release
  ([E-008-plan.md](../E-008-release-channels-and-staged-rollout/E-008-plan.md), "Pilot-group management").
  **Reject for this release**, and agree with the existing scope line.

**b) A prerelease-tag convention plus a filter** (e.g. `v1.2.0_aproda.9-pilot.1`, with `release` filtering
prerelease suffixes).

- *Buys:* reuses the existing tag machinery end-to-end, no SHA comparison code needed anywhere.
- *Costs:* this is precisely the mechanism the plan's own review already measured and rejected for a
  *different* reason that applies with equal force here: **B-40's second instance** shows the extension
  version pattern already accepts a prerelease suffix and would rank it above the prior release
  (`0.1.8-test.9 > 0.1.7`, verified in the review's fact-check #6). Adopting the same shape for the
  *layer* channel reintroduces exactly the risk B-40 names — a prerelease tag pushed by accident (or
  pushed deliberately for the pilot and never cleaned up) reaching all 25 machines the moment `release`'s
  tag-selection logic sees it, unless `release`'s tag filter is airtight. It also still needs a tag
  created and pushed for **every** pilot iteration, which is the exact overhead SHA-over-tag was chosen
  to avoid (the review's own "What I checked and found sound" section). **Reject** — worse on every axis
  than the plan's choice, not merely different.

**c) A per-project opt-in file** committed to the repo (e.g. `.aldc-pilot`).

- *Buys:* visible in code review, travels with the project.
- *Costs:* it is solving a problem that is **already solved**. The tracked `*.code-workspace` file is
  explicitly listed under `neverTouch`
  ([aproda-sync.json:138](../../tools/aproda-sync/aproda-sync.json)) — the syncer will never overwrite
  it — and it is a workspace-scope VS Code settings container, not merely a folder list. Setting
  `aprodaAldc.channel` / a branch-name setting at the **workspace level inside that already-tracked
  file** gives every property this alternative wants — committed, code-reviewable, project-scoped — for
  zero new files and zero new sync-manifest entries. The only reason this is not already the documented
  pilot procedure is that nobody wrote it down. **This is the one place I would add something the plan
  does not have,** not as a new mechanism but as a documentation line: "set the pilot's channel and
  branch in the tracked `*.code-workspace`'s workspace settings, not in User settings" — cheaper,
  reviewable, and self-documenting about which three machines/projects are piloting. **Confidence:
  Medium** — I have not verified that VS Code resolves `aprodaAldc.channel` correctly when set at
  workspace-file level ahead of user/global scope in this specific multi-root layout; the precedence is
  standard VS Code behavior but worth a five-minute manual check before writing it into the pilot
  runbook.

**d) Reusing the existing `pinned` channel differently** — let `pinnedVersion` accept a branch name or a
raw SHA instead of only a release tag, since `resolveReference()`'s checkout step
(`git checkout --detach <reference>`, [layerSource.ts:81](../../tools/aproda-vscode-extension/src/source/layerSource.ts))
already accepts any refspec, not just a tag.

- *Buys:* no new channel enum value, no new setting.
- *Costs:* `pinned`'s entire purpose today is "never report an update" — that is the frozen-version use
  case, and the plan is right to keep it that way (§3.1). A pilot needs the **opposite**: "report when
  the branch moves," which is the whole point of running the E-006 test scenario in §4. Overloading
  `pinnedVersion` to sometimes mean "frozen" and sometimes mean "track this and tell me" would require
  sniffing the setting's *value shape* (does it parse as `<core>_aproda.<n>` or not?) to decide behavior,
  which is an implicit, undocumented type discriminator sitting where an explicit enum value already
  reads cleanly. That is not simpler, it is the same case-split moved somewhere worse to find. **Reject**
  — the explicit fourth channel value is the right shape precisely because `pinned` and `branch` have
  opposite semantics that would otherwise be inferred from a string's format.

**e) Not staging at all — reduce the migration's blast radius so a pilot is unnecessary.**

- *Buys:* if the migration were reversible, B-40's argument for *why staging belongs in this release*
  (§1: "the staging mechanism is the safety net for shipping an irreversible migration") dissolves, and
  the whole channel-detection work could genuinely move to E-008 as a pure capability.
- *Costs:* the migration's irreversible steps are structural, not incidental. `Migrate-AprodaProjectLayout.ps1`
  rewrites the tracked `*.code-workspace` through `ConvertTo-Json` (comments lost, one `.bak`,
  [lines 199-204](../../tools/aproda-sync/Migrate-AprodaProjectLayout.ps1)) and deletes the root
  `aldc.yaml` ([lines 100-103](../../tools/aproda-sync/Migrate-AprodaProjectLayout.ps1)) as part of moving
  the toolkit root under D-19's real-git-root rule. Making the workspace-file rewrite non-destructive
  would mean preserving comments through a JSON round-trip (`.code-workspace` is JSONC) — a real,
  self-contained engineering task, but not a small one, and it does not touch the `aldc.yaml` deletion at
  all, which is the more consequential of the two. **Reject as a substitute for staging in this
  release** — it is a legitimate, independent improvement (less blast radius is always good) but it does
  not remove the need for a pilot path *now*, only for some future, less risky version of this same
  migration.

### Recommendation

**Keep the `branch` channel.** All four "avoid a new channel" alternatives are either heavier (allow-list),
riskier (prerelease tag), redundant (opt-in file — solved for free by the tracked workspace file), or a
type-discriminator smuggled into a string (`pinned` reuse). **Add:** document that a pilot sets its
channel/branch at workspace scope in the tracked `*.code-workspace`, not User settings — it is free and
makes "which 3 machines are piloting" answerable by `git log` on that file instead of by asking three
people. **Confidence: High** on rejecting the alternatives, **Medium** on the workspace-file addition
pending a quick precedence check.

---

## 3. Is `aldc.yaml` the right home for the applied ref?

**The plan's choice (🟩):** the syncer writes the delivered SHA into `aldc.yaml` as its own field.

### What the plan gets right, and what it understates

The move away from `globalState` is correct for the reasons given — it collapses existence and identity
into one file, which designs out the move/rename staleness problem the review flagged (Correction 2 /
`gitRoot.ts:24-47`). I would not reverse this.

**What §3.3 understates: the `dualVariant` mechanism, as it exists today, cannot do what is being asked
of it.** Reading the actual manifest and script:

```json
"rewrites": [
    { "match": "^toolkitRoot:\\s*\".*\"\\s*$", "project": "toolkitRoot: \".github\"", "fork": "toolkitRoot: \".\"" }
]
```
([aproda-sync.json:55-70](../../tools/aproda-sync/aproda-sync.json))

Every existing `dualVariant` rewrite substitutes a **static literal from the manifest** — `project` and
`fork` are fixed strings written once by a human, not values computed at run time
([Sync-AprodaLayer.ps1:355-364](../../tools/aproda-sync/Sync-AprodaLayer.ps1): `$target = $rw.$dstSide`
reads directly from the JSON). The applied-ref field needs the **opposite**: a value that differs on
every single sync run (`git rev-parse HEAD` in whatever was just checked out), written on the project
side only, with nothing at all on the fork side. That is not "one more `rewrites` entry" as §3.3's
phrasing suggests — it is a second *kind* of dual-variant behavior (computed-injection vs.
static-substitution), and the script has no hook for it today. **VERIFIED** by reading the rewrite loop
directly — there is no branch that shells out to git or accepts a runtime-computed value.

This is buildable (the syncer already has `$srcRepo`/the managed-cache path available, so
`git -C $srcRepo rev-parse HEAD` after the extension's own `checkout --detach`/`reset --hard` sequence
gives exactly the SHA that was applied — [layerSource.ts:79-81](../../tools/aproda-vscode-extension/src/source/layerSource.ts)
already performs that checkout before the syncer runs), but it is a materially different, larger change
to `Sync-AprodaLayer.ps1` than "inject this value on one side" implies, and it is the right thing for the
D-entry in §3.3 to say explicitly — otherwise whoever implements it will discover the gap mid-implementation,
which is exactly the pattern the independent review's Correction 1 already caught once in this same plan.

### Alternatives to `aldc.yaml` considered (beyond the ones already rejected in the plan)

- **A second, small git-ignored file next to `aldc.yaml`** (e.g. `aldc.appliedRef.json`), instead of a
  new field in `aldc.yaml` itself. *Buys:* keeps `aldc.yaml`'s schema untouched, avoids widening the
  `dualVariant` contract at all — a plain git-ignored file the syncer writes directly needs no
  manifest/sync-mechanism changes whatsoever, since it never has to survive a pull into a **fork's**
  copy of `aldc.yaml` (the field would be meaningless on the fork side anyway, per §3.2). *Costs:* one
  more file for a reader to know about, and it does not get the "the same file that would otherwise not
  exist correctly signals not-installed" property as cleanly if a partial reset leaves the new file but
  removes `aldc.yaml` (unlikely, but the plan's whole argument for `aldc.yaml` was "existence and
  identity become the same file" — a second file reintroduces exactly two files, two existence checks).
  **Verdict:** legitimate, and arguably **less risky to build** than widening `dualVariant` for a
  computed-injection case that has never existed before — but it gives up the plan's strongest stated
  benefit (single source of existence+identity) for implementation convenience. **I would not switch to
  this**, but flag it as the fallback if the `dualVariant` extension turns out to be harder to land safely
  than it looks; worth a sentence in the D-entry saying so.

### Recommendation

**Keep `aldc.yaml`.** But the D-entry §3.3 asks for must say, explicitly, that this requires a new
computed-injection capability in `Sync-AprodaLayer.ps1`, not merely a new `rewrites` entry — and should
name the git-ignored sidecar file as the documented fallback if that turns out to be riskier to implement
than estimated. **Confidence: Medium** — the storage choice is right, but the implementation-size estimate
implied by "one more `rewrites` entry" is off, and getting that wrong in an already-twice-slipped release
is a real risk (see Risks, below).

---

## 4. The one-channel-per-machine constraint — accept it, or fix the cache path now?

**The plan's choice:** accept the constraint as a documented pilot instruction; defer the real fix
(channel-aware cache path) to E-008.

### Measuring the actual cost of the "real fix"

```ts
this.cachePath = path.join(context.globalStorageUri.fsPath, "layer-cache", "fork");
```
([layerSource.ts:19](../../tools/aproda-vscode-extension/src/source/layerSource.ts))

Every method that touches the cache — `ensureManagedCache`, `repair`, `clearCache`, `describe` — reads
`this.cachePath` and nothing else; there is exactly one place that constructs it. Making it channel-aware
is contained to this constructor:

```ts
this.cachePath = path.join(context.globalStorageUri.fsPath, "layer-cache",
    channel() === "release" ? "fork" : `fork-${channel()}${channel() === "branch" ? `-${hash(branchName())}` : ""}`);
```

- **Backward-compatible for the 22 machines on `release`:** keeping the legacy `fork` path exactly for
  that channel means zero re-clone cost for the fleet that matters most.
- **Cost is paid only by whoever deliberately runs a non-`release` channel:** one extra full clone
  (`cloneManagedCache` already does a full, not partial, clone by design —
  [layerSource.ts:96-101](../../tools/aproda-vscode-extension/src/source/layerSource.ts) — so the cost of
  a second cache directory is "the same clone twice," not a new kind of operation).
  This is a genuinely small, mechanical, single-file change.

### Why I would still not pull it into this release

The plan's own §1 counter-argument is the correct lens here, and it argues against doing this now, not
for it: **B-34 and B-36 were both "it's small, take it in" additions that turned out wrong, one after it
had already shipped in two test builds.** "Small in code" is not the same claim as "safe to add to an
already-twice-slipped release without its own review cycle" — and this specific change touches the exact
code path (`ensureManagedCache`) that the plan's whole final test (§4) depends on working correctly for
the very first time on real machines. Adding a second variable (which cache path is in play) to that test
right when it is finally about to run for real is the kind of change the plan's own procedure (implement →
independent review → a test verified to fail without the fix → live evidence) exists to slow down, not
speed up.

### Recommendation

**Split the item, don't merely accept-or-build it whole.** Keep the *documented pilot constraint* for
this release exactly as planned — it is real safety at zero risk. But do not leave "channel-aware cache
path" filed as an E-008 policy item next to "rollout waves" and "pilot-group UI" — those need genuine new
product decisions; this does not. File it as its **own** fast-follow ticket, scoped exactly as measured
above, to be picked up the moment the E-006 pilot itself has run and the mechanism is proven — which
directly satisfies E-008's own prerequisite ("at least one real pilot run completed, so the policy is
designed against observed friction"). **Confidence: Medium** — the code-cost estimate is solid, the
scheduling call is a judgment about risk appetite this late in a slipped release, and reasonable people
could keep it bundled with E-008 instead.

---

## 5. The scope line against E-008 — anything that should move?

Per §4 above, the **channel-aware cache path** is the one item I would carve out of E-008's list and
schedule as an immediate, narrowly-scoped fast-follow rather than bundling it with "rollout waves,
pilot-group management, promotion gates" — those three are genuine policy/product work with no small
implementation, and correctly belong together.

Nothing else moves. The "prerelease policy" and "developer variants" items in E-008's table are
correctly deferred — they need a decision about discipline vs. enforcement that has no bearing on
whether B-39/B-40 are fixed, and pulling them in would repeat exactly the scope-growth pattern §1
warns about.

---

## 6. The missing-field rule for the 25 existing projects

**The plan's choice (§3.5 last row):** an explicit `unknown` status when `appliedRef` is absent,
resolved by the next apply, never reported as `current`.

**The rule itself is right** — it is the same "never silently report current" discipline (**B-6**) the
whole epic is built around, and it is the correctly minimal fix (one new branch in the status
computation, one new case in `showStartupResult`'s switch).

**What I would correct is the scope statement around it**, not the rule. Re-reading §3.2's own design:
*"On `edge`/`branch`, `layerVersion` is not consulted for status at all"* — which, read the other way,
means `appliedRef` is **never consulted on `release`/`pinned`** either. Every one of the ~25 production
machines is on `managed`/`release` (**B-40**'s own measured context). None of them will ever read the
`appliedRef` field, because their channel never triggers a comparison against it. So the "missing field"
scenario the plan worries about at fleet scale is actually a **first-run condition for whoever switches
a project to `edge`/`branch` for the first time** — a handful of pilot machines, not a 25-machine
migration concern. The plan's framing ("the 25 existing projects") overstates the blast radius of this
specific row; the *fix* is correctly scoped, the *motivating scenario* is not.

This matters for how the rule gets tested: the test case is "a project on `branch` whose `aldc.yaml` has
never had the field written" (i.e., right after flipping the channel setting, before the first Apply
Toolkit run under the new syncer) — not "any of the 25 existing `release` projects after the extension
upgrade," which never exercises this code path at all.

**Recommendation:** keep the `unknown` status and its rule exactly as designed; correct one sentence in
§3.5 to state the actual trigger (first switch to a SHA-based channel, not a fleet-wide upgrade
condition). **Confidence: High.**

---

## The simpler-design question

**Is there a materially simpler design that solves B-39 and B-40 together?**

The most tempting simplification — reuse `pinned` for the pilot instead of adding `branch` — was
evaluated in §2d and rejected: `pinned` and a pilot channel have opposite semantics (never report vs.
always report drift), so merging them relocates a case-split into implicit string-format sniffing rather
than removing it.

The next candidate: **could B-39 be fixed alone, with B-40 solved by something cheaper than a channel at
all** — e.g., a single machine-level "pin to this exact ref" setting that overrides channel entirely for
whoever sets it? This is close to what `pinned` already is, minus the tag-only restriction, and runs into
the same objection as §2d: it still needs a way to say "and please tell me when this moves," which is a
second setting either way. **I do not think B-40 can be solved with fewer moving parts than "a channel
value + a ref name"** — the channel is not incidental complexity, it is the minimum vocabulary needed to
express "I am intentionally tracking something that is not a release," which is the actual shape of the
problem.

Where a simpler design **does** exist is not in the mechanism but in the **storage question**: as argued
in §3, a plain git-ignored sidecar file avoids widening `dualVariant` at all, at the cost of one more
file to reason about. That is the one place I found where "simpler to implement" and "the plan's stated
design goal" pull in different directions, and it is worth the maintainer explicitly choosing rather than
discovering mid-implementation.

**Answer: no.** The plan's four-channel, SHA-based, syncer-written design is close to the minimum
mechanism the two findings actually require. The place to simplify is implementation risk (the
`dualVariant` extension), not the design shape itself.

---

## What I would not change, and why the alternatives lose

- **SHA over tags, manifests, GitHub API, content hashes, or moving tags** (§1) — every alternative either
  reproduces `ls-remote`'s answer at a real infrastructure cost, or actively reintroduces a failure mode
  (moving tags colliding with the existing non-force `fetch --tags` call) that SHA-over-branch-ref avoids
  by construction.
- **A dedicated `branch` channel over an allow-list, prerelease tags, or `pinned` reuse** (§2) — the
  allow-list is E-008's whole remaining scope wearing a smaller hat; prerelease tags reintroduce B-40's
  own second instance; `pinned` reuse hides a type discriminator instead of removing one.
- **`aldc.yaml` over `globalState`, the managed-cache HEAD, `workspaceState`, or `.git/config`** — this
  question was already closed correctly by the maintainer's proposal and the review's earlier rejections;
  I add only that the *implementation path* (§3) needs a named D-entry correction, not that the *storage*
  choice is wrong.
- **The `unknown` missing-field status over silently reporting `current` or `invalid`** (§6) — this is the
  epic's own founding principle (B-6) applied correctly; the only correction is to the scope sentence
  describing who is affected, not to the rule.

---

## Risks of my own proposals

- **The workspace-file recommendation (§2c)** assumes VS Code resolves a workspace-scoped
  `aprodaAldc.channel` value correctly ahead of any conflicting User-level setting in this specific
  multi-root `.code-workspace` layout. If precedence does not work the way I expect, documenting it as
  the pilot's primary mechanism would send someone debugging "why is my pilot machine still on release"
  instead of doing anything useful. **Mitigation:** verify precedence with a throwaway setting before
  writing it into the pilot runbook — a five-minute check, not a design risk, but a real one if skipped.
- **Splitting the channel-aware cache path out as an "immediate fast-follow" (§4)** could itself become
  exactly the "it's small, take it in" trap the plan warns about, if "immediately after" quietly becomes
  "let's just fold it into this PR since we're already touching `layerSource.ts`." The recommendation only
  holds if it is genuinely filed and scheduled as separate work with its own review, not merged into the
  E-006 changeset under time pressure.
- **The `dualVariant` computed-injection correction (§3)** could be read as scope growth in the other
  direction — flagging that the implementation is larger than the plan implies risks the maintainer
  deciding to build a bigger, more general "computed dual-variant" abstraction than this one field
  actually needs. The right-sized response is exactly what §3 recommends (a narrow git-command call added
  to the one syncer script, or the sidecar-file fallback), not a generalized plugin mechanism for future
  computed fields that do not exist yet.
- **Recommending the fallback sidecar file "if `dualVariant` turns out riskier than estimated"** creates a
  live fork in the design that has to be decided, not deferred, before implementation starts — leaving it
  as a conditional in this document is only useful if the D-entry §3.3 requires actually picks one, rather
  than carrying the ambiguity forward the way the original plan carried "what does installed mean" until
  the independent review caught it.
