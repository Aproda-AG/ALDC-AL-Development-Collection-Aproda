# Reference: Redeploy Recovery (ASINST and FKH)

> Loaded on demand by [`../SKILL.md`](../SKILL.md) and referenced by [`build-deploy.md`](build-deploy.md) and [`../../skill-aproda-fkh/SKILL.md`](../../skill-aproda-fkh/SKILL.md). This is operational recovery knowledge for an already approved deployment; it does not replace the DRV preflight or adapter selection.

## Purpose

Use this reference when a development redeploy retains the same app ID and version, or when a changed schema prevents installation. It applies the shared dependency rule to both adapters: remove apps in **reverse dependency order** and publish/install them in **normal dependency order**.

For a Base/Test pair, reverse order is Test then Base; normal order is Base then Test. For a larger app set, calculate the complete dependency graph before performing any recovery operation.

## Global-Scope Same-Version Recovery

Global-scope publishing is exceptional for FKH and requires an explicit user request. It remains available for ASINST and for explicitly requested FKH Global-scope work.

The recovery order for a same-version package whose schema changed is:

1. Uninstall and unpublish the owned apps in reverse dependency order.
2. Publish the same-version packages in normal dependency order.
3. Force-sync each published package in normal dependency order.
4. Install each package in normal dependency order.

`ForceSync` can discard data for changed tables or table extensions. It is suitable only for an acknowledged development environment, never as a production recovery technique. Inform the user briefly when the destructive synchronization is used; no additional confirmation is required once Global scope itself has been explicitly requested.

### ASINST

Use Remote PowerShell and NAV Management cmdlets. A previous synchronization can retain a stale table set even after unpublish and republish; `Install-NAVApp` then rejects the package. In that case the same-version recovery sequence above is the required remediation.

For retained tenant data from a prior version, use `Start-NAVAppDataUpgrade` only after a normal install fails and after the schema synchronization required by the package has completed.

### FKH

The normal FKH path is the Business Central Dev Endpoint:

```powershell
fkh publishapp --devScope --syncMode Add --sync --install
```

Dev scope permits same-version development redeployment and does not use the Global-scope uninstall/unpublish recovery procedure. An existing Global-scoped app requires a separately approved, one-time migration before it can be published through the Dev Endpoint.

For an explicitly requested FKH Global-scope recovery, use the same reverse-removal and normal publish/ForceSync/install order as ASINST. Do not treat Global recovery as an automatic fallback from a Dev Endpoint publish failure.

## DRV Operational Lessons

- Perform deployment in dependency order and fail at the first unsuccessful package; do not parallelize recovery publishes.
- For FKH targets, resolve the container by the acknowledged launch configuration's web-client hostname and use its `appLabel`.
- Preflight a live BC service with an HTTP(S) `HEAD` request. ICMP can be blocked by an Azure load balancer while the service remains usable.
- In this estate, PowerShell path-based script execution can be blocked by SRP. Load reusable scripts content-based with `[ScriptBlock]::Create((Get-Content -Raw))`.
- A terminal timeout around DRV does not by itself prove the test runner is hung. Inspect the runner result/XML and the process stage before diagnosing a runtime failure.
- After an installation failure, distinguish missing Microsoft test-library dependencies from application failures. Missing dependencies can make `Publish-NAVApp` or `Sync-NAVApp` appear to block without a PowerShell error; inspect package dependencies and the BC server event log.
