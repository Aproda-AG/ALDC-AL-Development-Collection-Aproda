# Reference: Triage Patterns (failure → cause → fix)

> Loaded on demand by [`../SKILL.md`](../SKILL.md). **The gold of this skill.**
> Each row is **falsifiable** — proven by a failing-then-passing test during the Audit Trail BC28 validation (26/26).

## How to use this file

When a test fails, match the symptom below → apply the fix → re-deploy → re-run. If no pattern matches, triage from first principles and **add a new row** here once proven.

## Patterns

### T-0 — `MISSING TARGET DEPENDENCY` at deploy ✅
- **Symptom:** the DRV run stops before any publish attempt with `MISSING TARGET DEPENDENCY on <server>: ...`.
- **Cause:** a configured app's manifest declares a dependency (typically ASFL, another Aproda module, or a third-party app) that is neither in the local app set nor already installed on the target — the preflight check (`Test-DeployRunVerifyTargetDependencies`) catches this before the fkh/NAV error would otherwise be opaque.
- **Fix:** this is **not** a code bug — do not touch AL source. Follow [`dependency-resolution.md`](dependency-resolution.md): match the named app against the known Aproda app sources, get the user's confirmation, install via `Install-DeployRunVerifyResolvedDependency`, re-verify, then re-run the loop.
- **Proven by:** D-52 (engine preflight added after a live gap surfaced on `flobi-wan-kenobi-gustavgerig-dev-deployment`, 2026-09-29).

### T-1 — Unhandled `Message` in the runner ✅
- **Symptom:** test fails on an unexpected UI `Message`, even though the code wraps it in `if GuiAllowed() then`.
- **Cause:** the client-driven runner has `GuiAllowed()=true`, so the guard does not suppress it (see `runner.md`).
- **Fix:** add `[MessageHandler] procedure MessageHandler(Msg: Text[1024])` to the test codeunit and `[HandlerFunctions('MessageHandler')]` to each affected test.
- **Proven by:** `StartEditUnlocksCertified`, `EndEditLogsAndRelocks`, `DeleteCapturesFinalState`, `ChecksumChainIntact`.

### T-2 — `xRec` unreliable in `tableextension OnBeforeModify` ✅
- **Symptom:** a guard comparing `Rec` vs `xRec` doesn't fire (or fires wrongly); before/after detection is broken.
- **Cause:** in a tableextension `OnBeforeModify` trigger, `xRec` is **not** a dependable before-image (it carries the new values, == `Rec`).
- **Fix:** re-read the persisted row for a reliable before-image: `RecBefore.Get(Rec."No.")` and compare against that.
- **Proven by:** Item `GuardedEditBlockedWhenBlocked` and the Routing parent guard.
- **BCQuality candidate:** this is a **generic, citable BC truth** → it belongs as an atomic knowledge file in BCQuality (`custom/knowledge/...`), **linked here, not duplicated**.
  > TODO: create/locate the BCQuality knowledge file and replace this note with its relative path.

### T-3 — Never nest a `Modify` inside `OnBeforeModify` ✅
- **Symptom:** "record changed by another user" / optimistic-concurrency errors, or a sibling routine that calls `Modify` from within a modify trigger.
- **Cause:** the triggering `Modify` is still in flight; a nested `Modify` collides.
- **Fix:** use a `PersistChanges` flag. Direct/interface callers pass `true` (do the `Modify`); the auto-complete path **inside** `OnBeforeModify` passes `false` so the **outer** `Modify` persists.
- **Proven by:** `EndEditLogsAndRelocks` (EndEdit set fields in-memory but never persisted → later `Get` re-read stale state). Fix = 3-arg `EndEdit(...; PersistChanges)`.

### T-4 — In-memory state never persisted ✅
- **Symptom:** a later `Record.Get()` reads stale values though the code "set" them.
- **Cause:** the routine mutated the record in memory but never called `Modify`.
- **Fix:** ensure a `Modify(true)` on the owning path (combine with T-3's flag where the call can originate inside a modify trigger).
- **Proven by:** `EndEditLogsAndRelocks`.

### T-5 — `SKU.Get` parameter order ✅
- **Symptom:** `Stockkeeping Unit` not found / wrong record.
- **Cause:** wrong key order. PK = **Location, Item, Variant**.
- **Fix:** `SKU.Get(LocationCode, ItemNo, VariantCode)`.
- **Proven by:** `SkuSystemWritePasses`, `SkuDeleteBlocked`.

### T-6 — Install fails on retained tenant data ✅ (deploy-side, former Management-DLL route)
- **Symptom:** `Install-NAVApp` errors that an earlier version is already installed.
- **Cause:** prior-version tenant data retained. Only seen on the former Management-DLL publish route, which the engine no longer uses; on the Dev Endpoint the equivalent is a `PUBLISH_REJECTED` sync/schema message (T-9).
- **Fix:** set `fkhSyncMode = ForceSync` for the run (D-39) or, for retained data from a version bump, follow `build-deploy.md`.

### T-7 — `PUBLISH_DUPLICATE` (HTTP 422) ✅ (measured on both adapters)
- **Symptom:** the publish stops with `PUBLISH_DUPLICATE`; `altool publishapp` exit 1 with `422 UnprocessableEntity`, *duplicate package ID*.
- **Cause:** the exact same package file (same package ID) is already published. A rebuild produces a new package ID even with an unchanged version.
- **Fix:** **inspect the state, never repeat the publish.** Rebuild (new package ID) and run again, or continue if the version is already installed and `Synced`. A `NotSynced` leftover is removed only after confirmation (`redeploy-recovery.md`).

### T-8 — `ROUTE-FALLBACK` lines and what triggers them ✅
- **Symptom:** the report shows `ROUTE-FALLBACK: <step> → <route> (<reason>)`.
- **Cause:** `altool` was missing, lacked the command, could not be started, got no HTTP answer, or (tests) returned no parseable result / an incomplete result. These are the **only** fallback triggers.
- **Not a fallback trigger:** red tests (`TestRunFailed`), compiler errors, sync/schema messages, HTTP 401/415/422. If a run shows a fallback after one of those, that is an engine defect — report it.
- **Action:** record the line in the phase report; a recurring `altool unavailable` or `could not be started` reason means the AL extension on the workstation needs attention (`Find-AprodaAlTool`).

### T-9 — `PUBLISH_REJECTED` with a schema message ✅
- **Symptom:** `PUBLISH_REJECTED` quoting a table-set / schema synchronization error.
- **Cause:** the changed schema cannot be applied with `Synchronize`.
- **Fix:** `fkhSyncMode = ForceSync` for the run (D-39: tell the user briefly; it can drop data of changed tables). Not `Recreate`; `forceUpgrade` only on an explicit request.

### T-10 — `Incomplete` altool test run ✅ (Q-13a, measured)
- **Symptom:** `ROUTE-FALLBACK: tests → webClient (Incomplete: requested codeunit(s) missing …)`, or `no test results (empty run)`.
- **Cause:** a non-test codeunit in the group stopped the run after the first group (`A task was canceled.`) while `succeeded` and `data.success` stayed `true`; or the group contained only a non-test codeunit (`total: 0`). `succeeded: true` alone does not prove a complete run.
- **Fix:** none needed — the web-client runner takes over for that run. Check that the test app's `Subtype = Test;` codeunits are the only ones in `testCodeunitRange`.

### T-11 — Red altool result ✅ (Q-9, measured)
- **Symptom:** `succeeded: false`, `errorDetails.code = TestRunFailed`; failing method with error text and AL call stack in `FailureDetails`.
- **Cause:** tests ran and failed. A blank-method completion record repeats the failure and is **not** counted (11 passed / 1 failed for one failing method, not 2).
- **Fix:** triage with T-1…T-5; the result is final for the run — it is never re-run on the web-client runner.

## Regression checklist after a shared-code fix

After any fix to **shared** code (edit-control codeunit, tableextension guard), re-confirm the **previously-green** tests in the same area didn't regress — not just the one you fixed. (E.g. the Routing guard re-read had to keep `StartEditUnlocksCertified`, `DeleteCapturesFinalState`, `ChildBlockedWhenNotInEdit`, `ChecksumChainIntact` green.)

## TODO

- Promote T-2 (and any other generic truths) into BCQuality knowledge files; replace inline text with citations.
- Add new patterns as they are proven (keep the "proven by" evidence column).
