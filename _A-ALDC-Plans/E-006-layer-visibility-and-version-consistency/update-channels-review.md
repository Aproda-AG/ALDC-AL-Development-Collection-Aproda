# Independent review — `update-channels.md`

> Reviewed against the code as of 2026-09-28. Nothing in this plan is implemented; this review is of the
> plan only. Read-only against all files except this one.

## Verdict: **SOUND WITH CORRECTIONS**

The core diagnosis (B-39, B-40) is correct and precisely evidenced — I reproduced both against the
current source. The design direction (channel-aware detection, SHA for moving refs, fail loud) is the
right one and the scope line against E-008 is mostly defensible. But the plan has three real holes that
would surface during implementation, not before: (1) it does not say what "installed" means for a SHA
comparison given `VersionService` currently only understands a `<core>_aproda.<n>` version string read
from `aldc.yaml`; (2) it misses that the managed cache is a **single, machine-wide** directory shared by
every project, not one per repository, which directly collides with interrogation point 2's "two projects
wanting different branches" scenario; (3) the update-check gating (`shouldRunStartupCheck`) is itself
global, not per-repository, which undercuts the value of a per-repository stored ref. None of these
invalidate the approach; all three need a paragraph in the plan before implementation starts.

---

## Fact check

| # | Claim (plan / B-39 / B-40) | Status | Evidence — what I measured |
|---|---|---|---|
| 1 | B-39: detection is `git ls-remote --tags … refs/tags/v*_aproda.*` → newest tag, channel-agnostic | **Verified** | [service.ts:64-84](../../tools/aproda-vscode-extension/src/version/service.ts) — `readAvailable()` never reads `channel()`; `check()` (line 21) calls it unconditionally |
| 2 | B-39: delivery is channel-aware — `edge` → `origin/aproda`, `pinned` → `v<version>`, else newest cached tag | **Verified** | [layerSource.ts:170-180](../../tools/aproda-vscode-extension/src/source/layerSource.ts) `resolveReference()` |
| 3 | B-39 "second instance": `localFork` still compares against release tags although the fork is the source | **Verified** | `check()` never inspects `sourceMode()`; `readAvailable()` always hits the remote tag list regardless of source mode |
| 4 | B-39 implied, not stated: `pinned` channel has the **same** defect, not just `edge`/`localFork` | **Verified, and the plan under-states it** | Under `pinned`, delivery is frozen at `v<pinnedVersion>` (layerSource.ts:172-176) but `VersionService.check()` still fetches the newest remote tag and will report `outdated` the moment any newer tag exists — exactly the B-39 mechanism, third instance. Not named in bcquality.md's B-39 text or in the plan's background section |
| 5 | B-40: tags are repo-global, `release` takes the highest, `pinned` needs 22 machines touched not 3 | **Verified** | `resolveReference()`'s release branch: `git tag --list v*_aproda.*` sorted, `.at(-1)` (layerSource.ts:181-186); `pinnedVersion()` is a single global setting (config.ts:70-72) so pinning 3 machines to an old value means writing that setting on the other 22, not the 3 |
| 6 | B-40 second instance: `compareExtensionVersions` would rank a `vscode-ext/v0.1.8-test.9` tag above a `0.1.7` release and offer it to everyone | **Verified by running the actual comparison logic** | `parseVersion` splits core/prerelease ([version.ts:35-38](../../tools/aproda-vscode-extension/src/extensionUpdate/version.ts)); core `[0,1,8]` vs `[0,1,7]` differs at index 2 → returns `1` before prerelease is even considered → `0.1.8-test.9 > 0.1.7`. `findExtensionUpdate` offers it (`compareExtensionVersions(current, available) < 0`, [service.ts:35](../../tools/aproda-vscode-extension/src/extensionUpdate/service.ts)) |
| 7 | Implied companion fact, not asked but worth confirming: does `0.1.8-test.9` also rank above the real `0.1.8`? | **Verified — no, correctly ranks below** | Core equal, then `!leftVersion.prerelease \|\| !rightVersion.prerelease` — left has a prerelease array, right does not → `leftVersion.prerelease ? -1 : …` → `-1`. A real `0.1.8` release tag supersedes the prerelease tag, as semver expects |
| 8 | §3.1: `git ls-remote <repo> refs/heads/<branch>` "returns the tip without a clone, ASCII-only — no encoding trap … (D-15)" | **Partially — citation is wrong** | D-15 in [decisions.aproda.md:142](../../.github/decisions.aproda.md) is "Deploy-Run-Verify Cycle standardized on the own engine" — unrelated. The actual encoding-trap comment lives in [Bootstrap-AprodaProject.ps1:83](../../tools/aproda-sync/Bootstrap-AprodaProject.ps1) and cites **D-19** ("consuming project keeps `.github/` at the real git root"), also not really about encoding — the nearby comment text is what the plan means, but neither D-number is the source of the encoding claim. `git rev-parse` mangling non-ASCII paths under a non-UTF-8 console is real (three separate scripts carry the same comment), but the parenthetical citation should be dropped or corrected, not `(D-15)` |
| 9 | §3.2: `aldc.yaml` is ruled out as storage — "git-ignored and written by the syncer... T-17 rejected write-back for `home`" | **Verified, and the ground is broader than stated** | `aldc.yaml`'s `layerVersion` (per **D-23**, [decisions.aproda.md:268-271](../../.github/decisions.aproda.md)) is a `<core>_aproda.<n>` string that a CI workflow validates matches the tag being created — the whole mechanism assumes a tagged release. A commit SHA has no such CI-validated relationship and would fail `isLayerVersion()` ([compare.ts:19-21](../../tools/aproda-vscode-extension/src/version/compare.ts)), landing `check()` in `invalid` today. The plan's rejection is correct but for a narrower reason than given |
| 10 | §3.2: managed cache `git rev-parse HEAD` ruled out — "shared across projects" | **Verified, and understated — see Correction 2** | `cachePath` is `context.globalStorageUri.fsPath/layer-cache/fork` ([layerSource.ts:19](../../tools/aproda-vscode-extension/src/source/layerSource.ts)) — `globalStorageUri` is one directory per **extension per machine**, not per workspace. It is not merely "shared across projects" in the abstract sense the plan uses to justify ruling it out as a *storage location* — it is the literal reason two projects cannot run different channels concurrently on one machine, which is a bigger problem than the storage question the plan frames it as |
| 11 | §3.3 row 4: the two-rung `resolveConfigurationPath`, "fixed under B-29", must stay in front of SHA comparison | **Verified** | [gitRoot.ts:145](../../tools/aproda-vscode-extension/src/env/gitRoot.ts) `resolveConfigurationPath`; behaviour matched by [version-service-config-path.test.js](../../tools/aproda-vscode-extension/test/version-service-config-path.test.js) — `.github/aldc.yaml` wins over root, absence of both → `notInstalled` |
| 12 | §4: pilot sets `channel: branch`; claims `initProject`/`runBootstrap` are unaffected by channel except through the source | **Verified** | `initializeProject` ([initProject.ts:14](../../tools/aproda-vscode-extension/src/commands/initProject.ts)) calls `source.ensure()` then `runBootstrap(repoRoot, layer.path, …)` ([bridge.ts:9](../../tools/aproda-vscode-extension/src/ps/bridge.ts)) — `layer.path` is always the fixed cache path, channel only decides what `ensureManagedCache()` checked that path out to. Correct as stated |
| 13 | E-006 migration is invasive/one-way: rewrites `.code-workspace` via `ConvertTo-Json` (comments lost), rewrites `.gitignore`, deletes root `aldc.yaml`, one `.bak` | **Verified** | [Migrate-AprodaProjectLayout.ps1:100-103](../../tools/aproda-sync/Migrate-AprodaProjectLayout.ps1) (root `aldc.yaml` removal), line 199-204 (`.bak` before `ConvertTo-Json` rewrite, comments explicitly called out as not preserved) |
| 14 | The plan's own open question ("is `globalState` keyed by repo root good enough for a moved/renamed repo") | **Verified as a real gap, unresolved by the plan** | `resolveTargetRepo()` returns the raw filesystem path ([gitRoot.ts:24-47](../../tools/aproda-vscode-extension/src/env/gitRoot.ts)); a moved/renamed folder is a different key with no migration path suggested anywhere in either document |

---

## Corrections

### 1. CRITICAL — the plan does not define what "installed" means for edge/branch comparisons

**What it says:** §3.2 stores "the applied ref" in `globalState`, and §3.3 talks about comparing a stored
SHA to a freshly resolved one.

**Why it's incomplete:** `VersionService.check()` today has exactly one axis: a version string read from
`aldc.yaml → aproda.layerVersion`, validated by `isLayerVersion()`'s regex, compared numerically by
`compareLayerVersions()`. None of that machinery accepts a SHA. The plan needs to say, explicitly, which
of these is true:
- (a) for `edge`/`branch`, "installed" moves entirely to the new `globalState` entry (SHA-vs-SHA), and
  `aldc.yaml`'s `layerVersion` field is not consulted for status computation on those channels — only for
  the pre-existing "is it installed at all" gate (§3.3 row 4); or
- (b) `readInstalled()` grows a second return value / a different code path per channel.

Whichever is chosen, `LayerUpdateStatus`'s `invalid` status (today reachable whenever `layerVersion`
doesn't match the version regex) needs a rule for "this project's channel doesn't use that field" or every
project on `edge`/`branch` reports `invalid` forever, which is a worse regression than B-39.

**Minimal replacement:** add one sentence to §3.2 stating (a) explicitly, and one line to §3.3 noting that
`isLayerVersion`/`compareLayerVersions` are release-channel-only and SHA channels bypass them entirely,
comparing directly against the stored `globalState` ref.

### 2. CRITICAL — the managed cache is one directory per machine, not per project; the plan's own interrogation question 2 is a real bug, not a hypothetical

**What it says:** Nothing — the design sketch never mentions this. §3.2 dismisses the managed cache as a
*storage location* for the applied ref ("shared across projects"), which is true, but stops there.

**Why it matters:** `cachePath` is fixed at `context.globalStorageUri.fsPath/layer-cache/fork`
([layerSource.ts:19](../../tools/aproda-vscode-extension/src/source/layerSource.ts)) — one path per
*machine* (VS Code's `globalStorageUri` is extension-scoped, not workspace-scoped). `channel` is itself a
setting that can be set at workspace level, so two projects open in two windows on the same machine, one
on `channel: release` and one on `channel: branch`, will run `ensureManagedCache()` against the **same**
on-disk checkout. Whichever `initProject` runs last wins; the other project silently applies whatever the
first left behind. This is exactly the scenario interrogation point 2 asks about, and it is not a corner
case for this release — the pilot itself needs at least one machine capable of comparing branch vs.
release behaviour, which is most naturally done by a developer flipping between two projects on one
machine, i.e. precisely the failure mode.

**Minimal replacement:** either (a) state explicitly that the pilot requires one *project* per *channel
setting* per *machine* — no machine may run two projects on different channels concurrently — and accept
that as a documented pilot constraint, or (b) fold the channel (and branch name, when set) into the cache
path, e.g. `layer-cache/fork-<channel>[-<branch-hash>]`, so concurrent channels don't collide. (a) is
cheaper and proportionate to a 3-machine pilot; (b) is the real fix and belongs in E-008 if deferred. The
plan should say which, not stay silent.

### 3. MAJOR — the startup-check interval gate is global across projects, undermining the per-repository ref

**What it says:** Nothing; not mentioned in §3.3's failure-mode table despite the review brief asking
about the interaction with `shouldRunStartupCheck`'s interval.

**Why it matters:** `shouldRunStartupCheck(context, intervalHours)` reads/writes
`context.globalState.get<number>("lastLayerUpdateCheck", …)` with **no repository key**
([startup/check.ts:43-44](../../tools/aproda-vscode-extension/src/startup/check.ts)). On a machine that
opens more than one AL project, checking project A resets the shared timer and project B's check can be
skipped for up to `intervalHours` even though B was never actually checked. This is orthogonal to
channel-awareness but the plan's whole premise — "record the applied ref **per repository**" — only pays
off if the check that consults it actually runs per repository. Combined with Correction 2, a
multi-project developer machine is doubly wrong today: same cache, same timer.

**Minimal replacement:** either key `lastLayerUpdateCheck` by repository root too (small, consistent with
the new applied-ref key), or explicitly scope this release to "single AL project per machine" and record
that as a stated limitation, not a silent one.

### 4. MAJOR — the citation `(D-15)` in §3.1 is wrong

**What it says:** "`git ls-remote … refs/heads/<branch>` returns the tip without a clone, ASCII-only — no
encoding trap of the kind that made the syncer avoid `git rev-parse --show-toplevel` (D-15)."

**Why it's wrong:** D-15 is "Deploy-Run-Verify Cycle standardized on the own engine" — a Test-Runner /
DLL-provisioning decision, unrelated to git output encoding. See Fact check #8.

**Minimal replacement:** drop the parenthetical citation, or replace it with a direct reference to the
comment in [Bootstrap-AprodaProject.ps1:83](../../tools/aproda-sync/Bootstrap-AprodaProject.ps1) /
[Sync-AprodaLayer.ps1:79](../../tools/aproda-sync/Sync-AprodaLayer.ps1) / [Initialize-AprodaProject.ps1:54](../../tools/aproda-sync/Initialize-AprodaProject.ps1),
none of which are pinned to a decision number for this specific point.

### 5. MINOR — B-39's own description under-states itself; the plan inherits the gap

**What it says:** update-channels.md frames B-39 as "edge delivers a branch but is told about releases"
and calls out `localFork` as "the milder version." `pinned` is not mentioned as an instance at all, even
though the plan's own §3.1 design table fixes it (`pinned → never reports an update`).

**Why it matters:** a reader auditing "did the fix cover everything B-39 named" would not know `pinned`
was in scope, because the finding never named it as broken. The fix is right; the paper trail is
incomplete.

**Minimal replacement:** one clause in §3.1 or the background section: "`pinned` has the same defect today
— the check ignores the frozen version and reports drift against the newest tag regardless."

### 6. MINOR — new `branch` setting is not accounted for in the settings-reset machinery

**What it says:** §3.1/§3.2 propose a "configurable branch," implying a new setting (parallel to
`pinnedVersion`).

**Why it matters:** every existing global setting is enumerated in `globalSettingKeys`
([config.ts:9-24](../../tools/aproda-vscode-extension/src/config.ts)), consumed by `resetGlobalSettings()`
and by the settings walkthrough. A new `branch`-name setting that isn't added there will survive a
"reset" and won't appear in the setup flow — a small thing, but it is exactly the class of miss this epic
exists to catch (a shipped setting the reset/setup UI doesn't know about).

**Minimal replacement:** one line noting the new setting key must be added to `globalSettingKeys` and (per
existing pattern) to the settings contribution in `package.json` with its own `enum`/description, and to
`aprodaAldc.channel`'s enum (currently `["release", "edge", "pinned"]`,
[package.json:183-192](../../tools/aproda-vscode-extension/package.json)).

### 7. NIT — "four failure modes" undercounts the modes actually named in this review's own reading

Not a defect in the plan's content, but the section title ("the four failure modes") should be revisited
once Corrections 2 and 3 are addressed — those are two more failure modes in the same family
(concurrent-channel collision, cross-project timer starvation), and the table format already fits them.

---

## Gaps — not mentioned at all

- **CI-gate bypass, unstated.** D-23 documents a GitHub Actions workflow that validates a version bump
  against `aldc.yaml` before a release tag is created — the `release` channel's entire trust model rests
  on that gate. `edge`/`branch` sidestep it completely (no CI validation of what's on a branch tip before
  it's offered as an "update"). That is presumably intentional for a pilot, but the plan never says so —
  it should state plainly that the `branch` channel offers **whatever is on the tip of the configured
  branch, with no CI gate**, which is a meaningfully different trust posture from every other channel and
  worth one explicit sentence given this epic's stated obsession with "a check that verifies nothing must
  never report current."
- **What un-pilots a machine.** The plan describes how 3 machines get onto `branch`, and E-008 asks "what
  promotes a branch to a tag" as an open question — but neither document says what happens to the 3
  pilot machines' *settings* once the pilot ends. If they are left on `channel: branch` after the feature
  branch is deleted (a scenario §3.3 already worries about for the SHA check), someone has to remember to
  flip 3 machines back to `release`. That's a two-line runbook note, currently absent from both files.
  Related risk explicitly asked for in the brief and not addressed elsewhere in this review: the ~22
  machines on `release` are unaffected as long as no tag is pushed during the pilot — true today — but
  nothing prevents someone from tagging the *next* unrelated release while the pilot is running, which
  would land on all 22 while the 3 pilot machines separately track the branch. Not a conflict, but worth
  one sentence acknowledging the two tracks are independent and can drift arbitrarily far apart during the
  pilot window.
- **`workspaceState` was raised in the brief and the plan never considers it.** It is the wrong choice
  (multi-root workspaces share one `workspaceState`, and the applied-ref-per-repo model wants a stable key
  independent of which workspace file happens to have the folder open) — but the plan should say why it
  was rejected, the same way it explains why `aldc.yaml` and the cache HEAD were rejected. Right now it
  simply isn't discussed, and a future reader has no way to tell "not considered" from "considered and
  rejected for a reason."
- **The project's own `.git/config` as storage was raised in the brief and is also not discussed.** It is
  arguably a *better* fit than `globalState` (survives a rename/move automatically, travels if the repo is
  cloned to a new machine, machine-local per clone via `.git` not being synced) with the downside of being
  one more thing that could theoretically be committed by accident if someone runs `git add -A` inside
  `.git` (extremely unlikely — `.git` itself is never tracked). Not necessarily the right call, but it is
  a closer analogue to how Git itself tracks per-clone state (e.g. `remote.origin.fetch`) than an
  extension's opaque key-value store, and deserves a rejection sentence if rejected.

## Open questions the plan should answer before implementation starts

1. Which of Correction 1's options (a)/(b) is intended — does `layerVersion` stop being consulted at all
   for `edge`/`branch`, or does it grow a second meaning?
2. Is "one channel per machine at a time" an acceptable, explicit constraint for this release (Correction
   2), or does the managed-cache path need to become channel/branch-aware before the pilot runs on any
   machine that also hosts a second, `release`-channel project?
3. Does `lastLayerUpdateCheck`'s gate get a repository key in this release, or is it explicitly left global
   and documented as a known limitation (Correction 3)?
4. Is `.git/config` genuinely worse than `globalState` for this specific use, or was it simply not
   considered? The plan should show its work here the way it did for `aldc.yaml` and the cache HEAD.
5. What is the runbook step for ending the pilot — who flips the 3 machines back, and when?

## What I checked and found sound

- The core B-39/B-40 diagnoses are accurate, precisely located, and not overstated — if anything B-39 is
  slightly under-stated (Correction 5).
- The decision to keep this in E-006 rather than defer it (§1) is well-argued: the migration's
  irreversibility genuinely does make the staging mechanism part of the release's safety net, not a
  separate capability. This is a correct call and better-reasoned than the "first position" it replaced.
- §3.3 row 4 (project reset, stale stored SHA) is the right failure mode to worry about most, and citing
  it back to B-23/B-34's "existence vs. identity" pattern is an accurate and useful connection — both were
  real, previously-shipped defects with exactly that shape.
- The SHA-over-tag choice for a moving branch is correct; there is no tag-based way to represent "whatever
  is currently on this branch" that wouldn't require creating and moving a tag on every commit, which
  defeats the purpose.
- `git fetch --tags --prune` (already used in `ensureManagedCache`) does fetch the standard `refs/heads/*`
  refspec in addition to tags — `origin/<branch>` will stay current for a `branch` channel using the
  existing fetch call, no additional fetch logic needed on the delivery side. Not stated in the plan, but
  it costs nothing extra, which is worth confirming rather than assuming.
- The scope line against E-008 is largely coherent: rollout policy, pilot-group UI, and promotion gates are
  genuinely separable from "make detection correct and give three machines a lever." The one soft spot is
  that both documents' "open questions" sections are near-verbatim duplicates (`globalState` keying,
  prerelease-tag policy) — harmless, but it means a reader can't tell from E-008 alone which questions are
  "still open because E-006 hasn't answered them yet" versus "genuinely E-008's to answer later."
