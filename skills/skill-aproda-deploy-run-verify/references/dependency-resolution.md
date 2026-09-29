# Reference: Missing-Dependency Resolution (ASINST and FKH)

> Loaded on demand by [`../SKILL.md`](../SKILL.md) → *Preflight gate*, and by [`../../skill-aproda-fkh/SKILL.md`](../../skill-aproda-fkh/SKILL.md) → *Missing Dependencies*. This is the adapter-agnostic counterpart to [`redeploy-recovery.md`](redeploy-recovery.md): that file recovers an already-approved deployment, this one closes a gap the target is missing before the first publish is even attempted.

## When this applies

`Invoke-AprodaDeployRunVerify` runs `Test-DeployRunVerifyTargetDependencies` before any publish attempt, for both adapters. If a configured app's manifest declares a dependency that is neither in the local app set nor already installed on the target, the engine throws `MISSING TARGET DEPENDENCY: ...` and stops — it never publishes anything in that state. Treat this error as the trigger for the procedure below, not as a generic deploy failure.

## The full closed loop

```
1. Engine preflight detects + names the gap  →  MISSING TARGET DEPENDENCY (engine, both adapters)
2. Agent matches the named app against the known Aproda app sources (below)
3. Agent offers the match to the user; waits for explicit confirmation — no match / no confirmation → stop and ask
4. Agent installs the confirmed file via Install-DeployRunVerifyResolvedDependency, in tier order
5. Agent re-runs Test-DeployRunVerifyTargetDependencies to confirm the gap is closed
6. Only then does the normal DRV loop proceed to publish the project's own apps
```

Steps 1 and 5 are the same engine function; step 4 is the only step that writes to the target, and it only ever runs against a file path the user has confirmed.

## Step 2 — Known Aproda app sources

See [`../../../.github/site-profile.aproda.md`](../../../.github/site-profile.aproda.md) → *Aproda App Sources* for the canonical fileshare locations (ASFL foundation layer, other Aproda modules, third-party/Fremd Module) and the `Archiv Signed` convention for older versions.

## Step 3 — Resolution is HITL, never automatic

A single unambiguous match is still not authorization to publish it unattended. Name the file and its path, and wait for explicit confirmation before installing it. If nothing matches, stop and ask the user directly; do not guess a substitute version or search elsewhere.

## Step 4 — Install in tiers, adapter-dispatched

Resolve and install in **tiers**, foundation-most first — apps within a tier still go through the project's own local dependency sort where more than one file is confirmed at once:

1. **ASFL** (Aproda Foundation Layer) — the base every other Aproda AppSource app depends on.
2. **Other Aproda modules** (public Cloud).
3. **Third-party / Fremd Module** apps.
4. **Project apps** (the normal DRV publish that follows once this loop closes).

Use `Install-DeployRunVerifyResolvedDependency -Cfg $cfg -AppFile <confirmed path> -Name <name> -Version <version>` for each confirmed file — it dispatches to the right adapter mechanics:

- **FKH** — `fkh publishapp --devScope --syncMode Add --sync --install`, the same Dev Endpoint path the normal loop uses.
- **ASINST** — `Publish-NAVApp -SkipVerification -Scope Tenant` → `Sync-NAVApp -Mode Add` → `Install-NAVApp`, with the same ForceSync/DataUpgrade escalation used elsewhere in the engine (see [`build-deploy.md`](build-deploy.md) → *Install-or-upgrade fallback*).

Do not hand-type these commands ad hoc — the function exists precisely so the mechanics stay tested and consistent across projects; only the file path and the decision to run it are human-supplied.

## Step 5 — Re-verify before proceeding

Re-run `Test-DeployRunVerifyTargetDependencies -Cfg $cfg` after every installed tier. A still-reported gap (e.g. a wrong or too-old confirmed version) must stop the loop again — never proceed to publish the project's own apps against a target that is still missing something.

## Constraints

- This procedure never runs unattended as part of the automatic loop — every install requires a prior human confirmation of the specific file.
- Do not confuse this with [`redeploy-recovery.md`](redeploy-recovery.md): that reference handles a same-version schema-changed redeploy of apps *already* approved for this target; this one handles a dependency the target has never seen at all.
