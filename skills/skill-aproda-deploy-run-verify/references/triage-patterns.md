# Reference: Triage Patterns (failure → cause → fix)

> Loaded on demand by [`../SKILL.md`](../SKILL.md). **The gold of this skill.**
> Each row is **falsifiable** — proven by a failing-then-passing test during the Audit Trail BC28 validation (26/26).

## How to use this file

When a test fails, match the symptom below → apply the fix → re-deploy → re-run. If no pattern matches, triage from first principles and **add a new row** here once proven.

## Patterns

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

### T-6 — Install fails on retained tenant data ✅ (deploy-side)
- **Symptom:** `Install-NAVApp` errors that an earlier version is already installed.
- **Cause:** prior-version tenant data retained.
- **Fix:** fall back to `Start-NAVAppDataUpgrade` (see `build-deploy.md`).

## Regression checklist after a shared-code fix

After any fix to **shared** code (edit-control codeunit, tableextension guard), re-confirm the **previously-green** tests in the same area didn't regress — not just the one you fixed. (E.g. the Routing guard re-read had to keep `StartEditUnlocksCertified`, `DeleteCapturesFinalState`, `ChildBlockedWhenNotInEdit`, `ChecksumChainIntact` green.)

## TODO

- Promote T-2 (and any other generic truths) into BCQuality knowledge files; replace inline text with citations.
- Add new patterns as they are proven (keep the "proven by" evidence column).
