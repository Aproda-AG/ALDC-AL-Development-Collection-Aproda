# E-008 — Release channels and staged rollout

> **Status (2026-09-28): not started, deliberately deferred.** The mechanism this epic builds on ships
> with **E-006** — see [`update-channels.md`](../E-006-layer-visibility-and-version-consistency/update-channels.md).
> What remains here is the *policy* layer on top of it.
>
> **Not part of the E-006 release.** If it creeps in, the release slips again — it already has, twice,
> on the phrasing "it's small, take it in".

---

## Why this exists

Origin: a test idea. *"Merge the feature branch, switch to the managed cache, and run the real scenario
on a real project — but without a release tag, so nothing actually rolls out."*

The idea was right and could not be executed, which is how the underlying gap surfaced:

- The update **check** is tag-based regardless of channel, so a branch-based channel is never told
  about its own branch (**B-39**).
- Tags are repository-global, so there is **no way to give a version to three machines without giving
  it to twenty-five** (**B-40**). With ~25 machines in production, that is not a theoretical limit.

E-006 absorbed the minimum: channel-aware detection, a `branch` channel, and the failure modes around
it. That was justified on its own terms — B-39 is a defect, and B-40 makes staging the safety net for
an irreversible migration.

**What is left is the part that is genuinely a product capability, not a defect fix.**

---

## Scope

| Item | Sketch |
|---|---|
| **Channel-aware cache path** | `layer-cache/fork-<channel>[-<branch-hash>]`. Today the managed cache is **one directory per machine** (`globalStorageUri`), so two projects on different channels collide — E-006 handles this with a documented "one channel per machine" pilot constraint, which is the cheap answer, not the right one |
| **Per-project channel** | Blocked by the row above; not a matter of demand |
| **Rollout waves** | Promote a version from pilot to a subset to everyone, as a recorded decision rather than an ad-hoc tag |
| **Pilot-group management** | Who is on what, visible somewhere other than 25 individual settings files |
| **Promotion gate** | What has to be true before a branch becomes a tag — is it a decision, or a check? Note that `edge`/`branch` bypass the D-23 CI gate entirely: they offer whatever is on the branch tip, unvalidated |
| **Developer variants** | A developer running their own ALDC variant long-term, without fighting the update check every window |
| **Applied ref in `.git/config`** | **Dropped 2026-09-28** — E-006 records the delivered SHA in `aldc.yaml` (written by the syncer), which gives the same move/rename resilience without putting extension state into `.git`. Kept here only so the option reads as *rejected*, not *forgotten* |
| **Prerelease policy** | Whether prerelease tags exist at all, and who may see them. The extension version pattern already permits them |

### Explicitly out

- Anything that duplicates what E-006's `update-channels.md` already delivers.
- A UI for its own sake. Two settings on three machines is not yet a problem worth an interface.

---

## Why it can wait

The pilot works today with two settings on three machines. That is not elegant, but it is sufficient,
and "sufficient and boring" is the right state for a mechanism whose first job is to reduce risk.

The policy layer becomes worth building when one of these is true:

- more than a handful of machines need different channels at once;
- someone has to ask "who is on what?" and cannot answer it in a minute;
- a promotion goes wrong and the reason is that nobody recorded the decision.

None of those is true yet.

---

## Prerequisites

- E-006's `update-channels.md` implemented, reviewed and **live-verified** — not merely merged.
- At least one real pilot run completed, so the policy is designed against observed friction rather
  than an imagined workflow.

---

## Open questions carried over

- Is `globalState` keyed by repository root the right home for the applied ref, or does that key need
  to survive a moved repository? **Answered 2026-09-28** — neither: the ref goes into `aldc.yaml`,
  written by the syncer, so it travels with the delivered layer and the question dissolves.
- Should `release` filter prerelease tags, or should such tags never be created? The second is cheaper
  and relies on discipline; the extension pattern already permits them, so discipline is currently the
  only thing preventing a prerelease reaching all 25 machines.
- Does a promotion need a gate, or is a recorded decision enough? A gate over an unreliable signal is
  gate theatre — the same argument that deferred T-26 in E-006.

