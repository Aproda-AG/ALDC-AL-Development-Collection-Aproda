# Update channels — channel-aware detection and a pilot path

> **Status (2026-09-28): planned, nothing implemented.** This is the part of the update-channel work
> that **blocks the E-006 release**. The rest — rollout policy, pilot-group management, the UI around it
> — is [`E-008`](../E-008-release-channels-and-staged-rollout/E-008-plan.md) and is deliberately not in
> this release.
>
> Findings: **B-39** (detection ignores the channel) and **B-40** (no pilot path, 25 machines) in
> [`bcquality.md`](bcquality.md).
>
> **Revised 2026-09-28 after an independent review** — [`update-channels-review.md`](update-channels-review.md),
> verdict *sound with corrections*. Three holes it found are folded in below and marked ⚡: the plan never
> said what *"installed"* means for a SHA comparison, it missed that the managed cache is **one directory
> per machine**, and it ignored that the update-check interval is global rather than per repository. One
> citation was simply wrong. The review is worth reading alongside this file — it verifies every factual
> claim here against the code, including the one with the largest blast radius (a prerelease extension tag
> reaching all 25 machines).
>
> **Revised again the same day 🟩** — the maintainer proposed recording the delivered SHA **in
> `aldc.yaml`**, written by the syncer, instead of in the extension's `globalState`. Adopted: it is
> smaller, survives a move or rename, and **designs out** a failure mode the earlier draft had to guard
> against. 🟩 marks what that changed. Two corrections went with it (§3.2), and it needs a D-entry
> (§3.3).
>
> **A third round, 2026-09-28 🔶** — [`update-channels-alternatives.md`](update-channels-alternatives.md)
> searched for better options than every decision here, and
> [`update-channels-alternatives-assessment.md`](update-channels-alternatives-assessment.md) checked that
> search. Outcome: **the design shape survives** — SHA + `ls-remote`, the `branch` channel and `aldc.yaml`
> were all kept after an explicit hunt for something better. Three corrections landed (🔶), one
> recommendation was rejected as net-harmful (committing the channel into the tracked `*.code-workspace`
> would enrol whoever *opens* the project, not the three designated machines), and one duplicate nobody
> had noticed — a second hardcoded cache path in `doctor.ts` — was fixed immediately, because it was a
> provable no-op today and a landmine the moment §3.4's cache path changes.

---

## 1. Why this is in the release and not deferred

It was almost deferred. The reasoning that moved it back in is worth keeping, because the first version
of it was wrong.

**First position (mine):** channel-aware detection is a capability, E-006 is a defect epic, therefore
it belongs in a separate epic and the final test can be done with a throwaway tag.

**The fact that changed it:** ~25 machines are already in production on `managed`/`release`.

- A throwaway tag is **not** throwaway. Tags are repository-global and `release` takes the highest one,
  so the tag would be offered to all 25 on their next window — a production rollout by accident.
- Worse, and this is what the first position missed entirely: **E-006 has no pilot path of its own.**
  There is today no way to hand a layer version to three machines without handing it to twenty-five.
- And what E-006 ships is invasive: the migration rewrites the tracked `*.code-workspace` through
  `ConvertTo-Json` (comments lost), rewrites `.gitignore`, deletes the root `aldc.yaml`, and is
  explicitly one-way. A `.bak` exists (**B-21**) — one file, one machine at a time, restored by hand.

So the staging mechanism is not a convenience for testing. **It is the safety net for shipping an
irreversible migration to 25 machines**, and that makes it part of this release.

> **The counter-argument, recorded so it stays visible.** This release has grown repeatedly on the
> phrasing "it's small, take it in", and the bill arrived each time: **B-34** and **B-36** were both
> quick additions of mine, both wrong, both found only by measurement — B-34 after it had already
> shipped in two test builds. Everything below goes through the same procedure as the rest: implement,
> independent review, a test verified to fail without the fix, then live evidence.

---

## 2. What is in scope here

| In | Why |
|---|---|
| Detection becomes channel-aware | **B-39** — this is a defect fix, in scope regardless of the pilot argument |
| `edge` / `branch` detected by **commit SHA** instead of release tag | The only honest signal for a moving branch |
| Record the **applied** ref per repository | Without it "is there something newer?" has nothing to compare against. **Written by the syncer into `aldc.yaml`** 🟩 — the marker lives with the artifact it describes |
| Widen the `dualVariant` contract | 🟩 First value computed at pull time and injected on one side only — needs a D-entry (§3.3) |
| Fail **loudly** when the ref cannot be resolved | A check that verifies nothing must never report "up to date" — see **B-6** |
| A `branch` channel with a configurable branch | Without it there is no pilot, which is the point of **B-40** |
| Keep prerelease tags away from `release` | The extension pattern already accepts them (**B-40**, second half) |

| Out — deferred to E-008 | Why it can wait |
|---|---|
| Rollout policy, staged waves | Needs the mechanism first; three machines set two settings by hand for now |
| Pilot-group management / UI | Same |
| Per-project channel overrides | **Not "no demand" — technically impossible today** ⚡: the managed cache is one directory per machine (§3.4), so a per-project channel cannot work until the cache path becomes channel-aware |
| Channel-aware cache path | The real fix behind §3.4's constraint |

---

## 3. Design sketch — ⚡ independent review, 🟩 maintainer's proposal, 🔶 alternatives round

### 3.1 Detection per channel

```
release  → highest tag matching v*_aproda.* WITHOUT a prerelease suffix
edge     → SHA of origin/aproda
branch   → SHA of origin/<configured branch>
pinned   → never reports an update
localFork→ never reports an update (the fork IS the source; today it compares against release tags)
```

`git ls-remote <repo> refs/heads/<branch>` returns the tip without a clone, and SHAs are ASCII — none of
the encoding trouble that made three of the sync scripts avoid parsing `git rev-parse --show-toplevel`
output. (An earlier draft cited *D-15* for that; wrong — D-15 is the Deploy-Run-Verify decision. The
rationale lives in the scripts' own comments and is not pinned to a decision number. ⚡)

> **Why not a tag that moves with the branch — the mechanical reason, not the stylistic one. 🔶** Reusing
> the release machinery against a tag repointed on every push would need no new comparison code at all,
> which is genuinely attractive. It fails on one line: the cache is refreshed with
> `git fetch --tags --prune` — **no `--force`** ([`layerSource.ts:77`](../../tools/aproda-vscode-extension/src/source/layerSource.ts)).
> Git refuses to clobber a local tag that already points elsewhere, so a moved tag would **silently stop
> updating** the first time it moved, and the check would report "current" while it was not — **B-6**
> again. SHA-over-branch-ref avoids that class by construction rather than by remembering a flag.

> **`pinned` is a third instance of B-39, not an unrelated row. ⚡** Delivery is frozen at
> `v<pinnedVersion>`, but the check fetches the newest remote tag and reports `outdated` as soon as any
> newer tag exists. The finding text named only `edge` and `localFork`, so an audit of *"did the fix cover
> everything B-39 listed"* would have missed it. The fix above covers it; the paper trail did not.

> **What `branch` means for trust, stated plainly. ⚡** Per **D-23** a CI workflow validates the version
> bump against `aldc.yaml` before a release tag is created — that gate is the entire trust model of the
> `release` channel. `edge` and `branch` bypass it: they offer **whatever sits on the tip of the
> configured branch, with no CI validation**. That is acceptable for a pilot and unacceptable as a
> default, which is why neither may ever become the shipped default. Given this epic's insistence that a
> check verifying nothing must never report "current", the weaker posture has to be written down rather
> than inferred.

### 3.2 What "installed" means on a moving channel — and where it is recorded 🟩

> 🟩 **Maintainer's proposal, 2026-09-28 — adopted, and it is better than what stood here.** The earlier
> draft (⚡ from the review) stored the applied ref in the extension's `globalState`, keyed by repository
> root, and explicitly ruled `aldc.yaml` out. **That ruling was right for the wrong case.** T-17 rejected
> the *extension* writing `home` into a repo file — a machine property the fleet bootstrap would reset.
> Here the **syncer** writes a property of the **delivery** into the file it already owns, and the next
> pull overwriting it is not a defect: that *is* the delivery.

`VersionService` has one axis today: a `<core>_aproda.<n>` string from `aldc.yaml`, validated by
`isLayerVersion()`, compared by `compareLayerVersions()`. **None of that accepts a SHA.**

**The design:**

- The syncer writes the delivered commit SHA into `aldc.yaml` as its **own field** — *not* into
  `layerVersion`, which keeps its meaning and its D-23 CI gate untouched.
- Detection compares that field against `git ls-remote <repo> refs/heads/<branch>` — the **remote tip**.
- On `edge`/`branch`, `layerVersion` is not consulted for status at all.

**Why the marker belongs with the artifact.** `aldc.yaml` is git-ignored, so a fresh clone or a reset
project has no `aldc.yaml` — and therefore no ref — and correctly reports *not installed*. **Existence
and identity become the same file.** That removes an entire failure mode: the old §3.5 row *"project
reset, stored SHA still present"* cannot occur, because there is nothing left to be stale. It also
survives a move or rename for free, which the `globalState` key did not.

**The consequence that must not be overlooked:** `LayerUpdateStatus.invalid` fires today whenever
`layerVersion` fails the regex. Without an explicit rule, every project on `edge`/`branch` would report
`invalid` forever — worse than the defect being fixed. So `isLayerVersion` / `compareLayerVersions`
become **release-channel-only**.

**Two corrections to the proposal as made:**

1. **The comparison source is `ls-remote`, not the managed cache.** Comparing against the cache would
   mean a fetch plus checkout on every window start, with network failures and lock contention against a
   concurrently running *Apply Toolkit*. `ls-remote` reads the remote tip without touching the cache; the
   cache is only updated when someone accepts the update.
2. **The `localFork` accuracy worry dissolves.** A dirty working tree means the recorded commit does not
   describe what was applied — correct, but §3.1 already decided `localFork` **never reports an update**.
   The value is written and never compared; it is diagnostic only.

**`appliedRef` is not CI-validated.** `layerVersion` is (D-23); the SHA says *"this arrived here"*, never
*"this was checked"*. That distinction has to sit next to the field, or it will eventually be read as a
release identity.

### 3.3 What this requires as a decision, not just as code

> **Recorded as [D-50](../../.github/decisions.aproda.md) on 2026-09-28** — written before any
> implementation, as the D-16 steward guardrail requires. This section stays the working trail; D-50 is
> the durable record.

Today `aldc.yaml` diverges per side by **one static line** (`toolkitRoot`). The applied ref would be the
first value **computed at pull time**, and it belongs on the project side only — the fork is not a
consumer. That widens the `dualVariant` contract from *"rewrite this line"* to *"inject this value on one
side"*.

**This is a new behaviour class in the syncer, not one more manifest entry. 🔶** An earlier draft of this
section undersized it. The rewrite loop reads a **literal from the manifest** —
`$target = $rw.$dstSide` ([`Sync-AprodaLayer.ps1:355`](../../tools/aproda-sync/Sync-AprodaLayer.ps1)),
with the value coming straight from JSON (`"project": "toolkitRoot: \".github\""`). No branch in that
loop accepts a runtime value or shells out. Supporting a computed one means a new conditional path plus a
`git rev-parse HEAD` against the source. Still modest — but it is code in the syncer, not configuration.

That is **D-18 territory and needs its own D-entry** before implementation — written down, not slipped in
with the code. The same entry should record that `Migrate-AprodaProjectLayout.ps1` moves `aldc.yaml`
from the repo root to `.github/`, and the field must survive that move.

**Rejected alternatives, so "not considered" stays tellable from "considered and rejected":**

| | Verdict |
|---|---|
| Extension `globalState`, keyed by repository root | **Superseded.** Worked, but a moved or renamed repository cost a spurious prompt, and it kept existence and identity in two different places |
| Managed cache `git rev-parse HEAD` | **No.** Wrong granularity — see §3.4 |
| `workspaceState` ⚡ | **No.** A multi-root workspace shares one `workspaceState`, and the key must not depend on which workspace file has the folder open |
| The project's `.git/config` ⚡ | **No longer needed.** It was the better answer only as long as the ref lived outside the delivered layer. `aldc.yaml` gets the same move/rename resilience without putting extension state into `.git` |

### 3.4 The managed cache is one directory per machine ⚡

Not a storage detail — a constraint on the pilot, and the first draft missed it entirely.

```ts
this.cachePath = path.join(context.globalStorageUri.fsPath, "layer-cache", "fork");
```

`globalStorageUri` is scoped to the **extension**, not the workspace. One checkout, `--detach`ed to one
reference, shared by every project on the machine. `channel` however can be set per workspace — so two
windows, one on `release` and one on `branch`, run against the *same* on-disk checkout. Whichever
`initProject` runs last wins, and the other project silently applies what the first left behind.

**Decision for this release: a documented pilot constraint, not a code change.** A pilot machine runs
**one channel at a time**; no machine may hold two projects on different channels concurrently. Three
machines, one channel each — proportionate.

**The real fix** — folding channel and branch into the cache path (`layer-cache/fork-<channel>[-<hash>]`)
— is E-008. Writing it down here matters: if the pilot machine also opens a `release` project, the
constraint is violated and the result looks like a product defect.

**One landmine defused early 🔶.** `doctor.ts` rebuilt the same cache path from the same parts instead of
asking `LayerSource` — two constructions of one fact, agreeing today. Had the path become channel-aware
first, *the diagnostic command* would have reported the wrong one, in exactly the situation someone runs
it to debug this collision. Fixed now rather than with E-008: a provable no-op today (both expressions
yield the identical string), which is a different risk class from the logic changes that produced **B-34**
and **B-36**.

> **Rejected as a pilot mechanism 🔶:** committing `channel`/branch into the tracked `*.code-workspace`.
> It works mechanically — the file is in `neverTouch` and workspace-scope settings do resolve — and it is
> **backwards**: it enrols whoever *opens the project*, not the three designated machines, and because the
> cache is machine-wide it would repoint an uninvolved colleague's other `release` projects too. It also
> survives *Reset Toolkit Cache and Settings*, which only clears Global scope. The pilot's unit is the
> **machine**, so the setting stays at **User** scope.

### 3.5 The failure modes that must be covered

Seven. The first draft had four, the review added two ⚡, the maintainer's proposal **removed** one 🟩 by
making existence and identity the same file, and the alternatives round added two and narrowed one 🔶.

| Case | Required behaviour |
|---|---|
| Branch deleted or renamed → `ls-remote` empty | Report **unavailable**, loudly. Reporting "current" here is **B-6** exactly: a check that verified nothing, passing |
| Network failure | Same — never a silent "current" |
| Force-push / rebase on the branch | SHA differs → offer the update. Correct as-is |
| Two projects, two channels, one machine ⚡ | Out of scope by constraint (§3.4) — but the constraint must be **stated in the pilot instructions**, or the collision reads as a defect |
| Interval gate is global, not per repository ⚡ | `shouldRunStartupCheck` reads `globalState.lastLayerUpdateCheck` with **no repository key**, so checking project A suppresses project B for up to `intervalHours`. A per-repository applied ref only pays off if the check consulting it also runs per repository. **Decision: key it by repository root** |
| **The field is absent on first switch 🔶** | The one new failure mode this design introduces — and it is **narrower than an earlier draft claimed**. It does *not* affect the fleet of 25: they run `release`, where detection stays tag-based and the field is never read. It is a **first-run condition for whoever switches to `edge`/`branch`**, resolved by the first apply. It must still resolve to *unknown* — never to "current" (**B-6**) and never to an invented update |
| Branch repointed without a fresh apply 🔶 | A machine moved `release → branch → release → branch`, or whose branch name is changed without re-applying, carries a **stale** `appliedRef` from an older branch. Compared against the *new* branch's tip it simply mismatches and reports `outdated` — safe, never a false "current". Stated here because "safe by construction" and "untested" look identical in a design document |

> **Removed by the proposal 🟩:** *"project reset, stored SHA still present."* With the ref inside the
> git-ignored `aldc.yaml`, a reset project has no ref at all and correctly reports *not installed*.
> The old row existed only to bridge two separate sources of truth — the existence-vs-identity split
> that let **B-23** through a 30-point acceptance list and **B-34** through its own regression test.
> Here it is designed out rather than guarded against.

### 3.6 Settings plumbing ⚡

Small, and exactly the class of miss this epic exists to catch: a shipped setting the reset and setup
flows do not know about.

- the new branch-name key goes into `globalSettingKeys` (`config.ts`), or it survives *Reset Toolkit
  Cache and Settings* and never appears in the setup walkthrough;
- `aprodaAldc.channel`'s enum in `package.json` is `["release", "edge", "pinned"]` today and must gain
  `branch`, with its own description.

---

## 4. What this unblocks

The final E-006 test, which has never run: the **managed** path — the one ~98% of machines actually
use. Every run so far used `localFork`.

```
1. merge the feature branch, no tag
2. three machines set channel = branch, branch = <feature branch>
3. the other 22 stay on release and see nothing
4. test the real flow:
   a. skip the extension update  -> no toolkit prompt may follow   (B-38)
   b. take the extension update, then the toolkit update -> clean update + migration
```

Step 4a is only meaningful once a layer update is genuinely available — otherwise "correctly
suppressed" cannot be told apart from "nothing to offer". That is why the detection fix comes first.

### Ending the pilot — the part nobody remembers ⚡

The first draft described how three machines get *onto* `branch` and said nothing about getting off.

1. Cut the tag **first**, so `release` has the version before anyone leaves the pilot.
2. Flip the three machines back to `channel: release` — by hand, there is no fleet mechanism (that is
   E-008).
3. **Only then** delete the feature branch. Deleting it while a machine still points at it produces the
   *"branch deleted"* failure mode of §3.5 — which now reports loudly, but there is no reason to trigger
   it deliberately.

**The two tracks drift, and that is fine.** While the pilot runs, nothing stops an unrelated release
being tagged — the 22 machines take it, the 3 pilot machines keep tracking the branch, and the two lines
can diverge arbitrarily far. Not a conflict, but worth knowing before it is discovered in the middle of
a pilot.

---

## 5. Open questions

*Most of the original set is now decided — what "installed" means and where it is recorded (§3.2 🟩), the
cache-granularity constraint (§3.4), the interval-gate key (§3.5). The storage question closed itself: the
proposal removed the move/rename problem instead of answering it. What is left:*

- What exactly does a **missing** `appliedRef` mean on a first switch to `edge`/`branch` (§3.5)? It must
  resolve to *unknown*, never to *current* — but the wording of that rule is not written yet, and it is
  the most forgettable part of this design.
- Should `release` filter prerelease tags, or should prerelease tags simply never be created? The second
  is cheaper but relies on discipline — and discipline is currently the only thing that has kept a
  `vscode-ext/v0.1.8-test.N` tag from reaching all 25 machines.
- After the pilot: what promotes a branch to a tag — a decision, or a gate? (E-008)
