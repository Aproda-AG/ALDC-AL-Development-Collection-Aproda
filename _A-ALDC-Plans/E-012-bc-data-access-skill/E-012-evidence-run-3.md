# E-012 — Evidence report, run 3 (session use, one install + safe clean-up with data deletion)

## 1. Result and decision proposals

| Item | Result | Proposal |
|---|---|---|
| **Session use** | **Stable.** One install, 48 requests over 16 min 53 s (burst of 27, 5 parallel, idle 5 and 10 min, an error in the middle, 3× 1000 rows): 47× 201, 1× 400 (intended), **no 404 / 429 / 5xx**, no stale read, no slowdown. p50 143 ms, p95 410 ms, max 615 ms. | Adopt "one install per support session, many queries". No client-side throttling needed for sequential use; up to 5 parallel calls are fine. |
| **`id` / insert pattern (F-20)** | **The colleague's original pattern works** when the client sends `id`: `if IsNullGuid(Rec.Id) then Rec.Id := CreateGuid(); … Rec.Insert(false); exit(false);` → 201, `id` echoed, result filled (Q-S.1). Without `id` still 201 + empty `result` + zero GUID (Q-S.5). Reusing an `id` → 201 with the new query's result, no 409 (Q-S.4). | Keep the original pattern (5.1) in the final app. The client **must** send a new GUID per request; treat `201` with an empty `result` as a client error ("id missing"). Duplicate ids are harmless (each request is its own temporary instance). |
| **Readiness (F-22)** | After `Completed`: first install **0 × 404**, first 201 0.3 s after `T_completed`; re-install **2 × 404**, first 201 **10.7 s** after `T_completed`. 404 body: `BadRequest_NotFound: No HTTP resource was found that matches the request URI …/dataRequests…`. | Readiness rule: after `Completed`, retry the first query on HTTP 404 `BadRequest_NotFound` every 5 s, give up after 3 min. Install itself took 93–123 s (run 2: 56 s) → keep the 10-min deployment poll timeout. |
| **Clean-up with data deletion** | **Works.** `POST …/extensions(<packageId>)/Microsoft.NAV.uninstallAndDeleteExtensionData` → **204** (487–801 ms), **no body / no extra parameter**, `isInstalled = false` after 2.8–3.3 s. The package stays **published** → `Microsoft.NAV.unpublish` still required (204). Re-install of the same `.app` after delete-data clean-up is allowed (same `packageId` reused). Repeat call on an unpublished package → 404 `BadRequest_ResourceNotFound`. | Skill "ensure clean" = `uninstallAndDeleteExtensionData` (installed packages) → `unpublish` (all packages), 404 tolerated. Note: the prototype has only a temporary table, so no persisted data was actually deleted (§6). |
| **Guard** | **Works.** Every destructive call passed `Assert-OurPackage` first. Negative tests threw before any call: foreign PTE *Data Administration (DA)* (**also publisher `Aproda AG`, also PTE** — rejected on `id` + `displayName`), Microsoft Global app, malformed id, unpublished package (lookup 404). | Adopt §5 as the skill engine core. Publisher + PTE alone is **not** a sufficient guard — `id` and `displayName` are mandatory checks. |

## 2. Header

| | |
|---|---|
| Date | 2026-11-13, 16:45–17:12 (CET) |
| VS Code / harness / shell | 1.144.0 / Copilot Local, agent mode / PowerShell 7.6.9 |
| AL extension / compiler | `ms-dynamics-smb.al-18.1.2842859`, built through the `al-mcp` server (`al_addproject` + `al_build`) |
| Account type | Florian, GDAP partner (signed in himself) |
| Auth | run-2 flow (auth code + PKCE, system browser, `HttpListener` localhost). Login 9.6 s, account picker only. Claims: `aud = https://api.businesscentral.dynamics.com`, `tid = 7391b259-…-25eb4469ed`, `scp = Financials.ReadWrite.All`, `roles` empty, `appid = 1950a258-227b-4e31-a9cf-717495945fc2`, lifetime **73.2 min** (`expires_in` 4091 s; run 2: 84.3 min), refresh token returned (not stored) |
| Tenant / environment | `7391b259-9b54-46a9-9722-2d25eb4469ed` / `Develop_Integration_TogaFood` (Sandbox, BC 28) |
| Company | Toga Food AG, `e276d4c8-e459-f111-a820-7ced8d437289` |
| App | `ab23bc15-d3c6-4fc6-b5bb-28c447bf8b6e`, `Aproda BC Data Access (prototype)`, `Aproda AG`, version **1.0.1.0**, `.app` 8 294 B, 0 diagnostics, built on the first attempt |
| Package id | `165c394c-bd98-4e60-b4f9-8d1777b629da` (L and R — the same package id both times) |
| Acknowledgements | L.0 16:47 (incl. Block R and Q-S.9), C.0 17:07, C.7 raw-call exception 17:09 — all by Florian |

**Prototype change (§5.1, only change besides the version):** page 91050 `OnInsertRecord`

```al
ResultTxt := DataAccessMgt.ProcessRequest(RequestTxt);
if IsNullGuid(Rec.Id) then
    Rec.Id := CreateGuid();
Rec.Result.CreateOutStream(ResultOutStream, TextEncoding::UTF8);
ResultOutStream.WriteText(ResultTxt);
Rec.Insert(false);
exit(false);
```

The 1.0.1.1 fallback (`exit(true)`) was not needed.

## 3. Lifecycle

`<Auto>` = `…/api/microsoft/automation/v2.0/companies(<c>)`.

| Step | Request | Status | Duration | Notes |
|---|---|---|---|---|
| 0.3 | `GET <Auto>/extensions?$filter=id eq <app>` (+ guard per row) | 200 | 621 ms | empty; tenant total 86 |
| L.1 | `POST <Auto>/extensionUpload` `{"schedule":"Current version","schemaSyncMode":"Add"}` | 201 | 393 ms | |
| L.1 | `PATCH <Auto>/extensionUpload(<systemId>)/extensionContent` (octet-stream, `If-Match: *`) | 204 | 186 ms | |
| L.1 | `POST <Auto>/extensionUpload(<systemId>)/Microsoft.NAV.upload` | 200 | 2 742 ms | |
| L.2 | poll `GET <Auto>/extensionDeploymentStatus` every 5 s (client filter: name + `appVersion` + `startedOn` ≥ start − 2 min) | 200 | **123 s** to `Completed` | `T_completed` 16:49:46; `operationType = Upload` |
| L.3 | Q.1 every 5 s until 201 | 201 | **0.3 s** after `T_completed` | 0 × 404 |
| L.4 | `Get-OurPackages` | 200 | — | 1 package, 1.0.1.0, `isInstalled = true` |
| C.1 | `Get-OurPackages` | 200 | — | `165c394c-…`, 1.0.1.0, installed |
| C.2 | guard → `POST <Auto>/extensions(<packageId>)/Microsoft.NAV.uninstallAndDeleteExtensionData` (no body) | **204** | 801 ms; uninstalled after **3.3 s** | no confirmation / extra parameter required; empty response body |
| C.3 | `Get-OurPackages` | 200 | — | **unchanged**: same package, `isInstalled = false` (still published) |
| C.4 | guard → `POST <Auto>/extensions(<packageId>)/Microsoft.NAV.unpublish` | 204 | 1 530 ms | |
| C.5 | `Get-OurPackages` | 200 | — | empty; tenant total 86 |
| C.6 | guard negative tests (lookup only, **no** lifecycle call) | — | — | see §5 messages |
| C.7 | `POST <Auto>/extensions(<unpublished packageId>)/Microsoft.NAV.uninstallAndDeleteExtensionData` — guard fails (lookup 404), raw call made as an **exception approved by Florian** | **404** | 182 ms | `{"error":{"code":"BadRequest_ResourceNotFound","message":"Resource not found for the segment 'extensions'.  CorrelationId: …"}}` |
| R.1 | L.1–L.3 with the same `1.0.1.0` `.app` | 201 / 204 / 200 | **93 s** to `Completed` | allowed after delete-data clean-up; same `packageId` again |
| R.1 readiness | Q.1 every 5 s | 404, 404, 201 | first 201 **10.7 s** after `T_completed` (17:11:09 → 17:11:20) | 2 × 404 |
| R.2 | Q.1 | 201 | 206 ms | 10 rows, `id` echoed |
| R.3 | Block C again (guard → delete-data uninstall 204 / 487 ms / 2.8 s; unpublish 204 / 1 374 ms) | — | — | empty; tenant total 86 |
| D.1 | `Invoke-EnsureClean -DeleteData` (no-op on the empty state) + `Get-OurPackages` | 200 | 573 ms | 0 packages |

## 4. Session log (Block S)

`POST <ProtoApi>/companies(<c>)/dataRequests`, body `{"id":"<new guid>","request":"<json string>"}` unless noted. Query pool Q.1–Q.9 = run-2 request JSONs (run-2 report §6). `id` column: *echoed* = response `id` equals the sent `id`. Rows L.3 and R.x are readiness/re-install probes, not part of the Block S statistics.

| # | Case | Query | Time | Status | ms | Bytes | Rows | id | Error |
|---|---|---|---|---|---|---|---|---|---|
| 1 | L.3 | Q.1 | 16:49:46.432 | 201 | 265 | 1497 | 10 | echoed | |
| 2 | Q-S.1 | Q.1 | 16:50:08.323 | 201 | 227 | 1497 | 10 | echoed | |
| 3 | Q-S.2 r1 | Q.1 | 16:50:08.648 | 201 | 143 | 1497 | 10 | echoed | |
| 4 | Q-S.2 r1 | Q.2 | 16:50:08.821 | 201 | 221 | 651 | 1 | echoed | |
| 5 | Q-S.2 r1 | Q.3 | 16:50:09.075 | 201 | 199 | 903 | 5 | echoed | |
| 6 | Q-S.2 r1 | Q.4 | 16:50:09.305 | 201 | 615 | 2063 | 20 | echoed | |
| 7 | Q-S.2 r1 | Q.5 | 16:50:09.947 | 201 | 165 | 14272 | 99 | echoed | |
| 8 | Q-S.2 r1 | Q.6 | 16:50:10.158 | 201 | 137 | 4281 | 57 | echoed | |
| 9 | Q-S.2 r1 | Q.7 | 16:50:10.320 | 201 | 125 | 10030 | 151 | echoed | |
| 10 | Q-S.2 r1 | Q.8 | 16:50:10.486 | 201 | 115 | 3173 | 10+20 | echoed | |
| 11 | Q-S.2 r1 | Q.9 | 16:50:10.629 | 201 | 410 | 131933 | 1000 | echoed | |
| 12 | Q-S.2 r2 | Q.1 | 16:50:11.075 | 201 | 67 | 1497 | 10 | echoed | |
| 13 | Q-S.2 r2 | Q.2 | 16:50:11.168 | 201 | 147 | 651 | 1 | echoed | |
| 14 | Q-S.2 r2 | Q.3 | 16:50:11.345 | 201 | 90 | 903 | 5 | echoed | |
| 15 | Q-S.2 r2 | Q.4 | 16:50:11.464 | 201 | 151 | 2063 | 20 | echoed | |
| 16 | Q-S.2 r2 | Q.5 | 16:50:11.640 | 201 | 125 | 14272 | 99 | echoed | |
| 17 | Q-S.2 r2 | Q.6 | 16:50:11.792 | 201 | 127 | 4281 | 57 | echoed | |
| 18 | Q-S.2 r2 | Q.7 | 16:50:11.946 | 201 | 167 | 10030 | 151 | echoed | |
| 19 | Q-S.2 r2 | Q.8 | 16:50:12.140 | 201 | 81 | 3173 | 10+20 | echoed | |
| 20 | Q-S.2 r2 | Q.9 | 16:50:12.256 | 201 | 149 | 131933 | 1000 | echoed | |
| 21 | Q-S.2 r3 | Q.1 | 16:50:12.454 | 201 | 159 | 1497 | 10 | echoed | |
| 22 | Q-S.2 r3 | Q.2 | 16:50:12.642 | 201 | 64 | 651 | 1 | echoed | |
| 23 | Q-S.2 r3 | Q.3 | 16:50:12.734 | 201 | 92 | 903 | 5 | echoed | |
| 24 | Q-S.2 r3 | Q.4 | 16:50:12.852 | 201 | 69 | 2063 | 20 | echoed | |
| 25 | Q-S.2 r3 | Q.5 | 16:50:12.946 | 201 | 76 | 14272 | 99 | echoed | |
| 26 | Q-S.2 r3 | Q.6 | 16:50:13.052 | 201 | 59 | 4281 | 57 | echoed | |
| 27 | Q-S.2 r3 | Q.7 | 16:50:13.139 | 201 | 64 | 10030 | 151 | echoed | |
| 28 | Q-S.2 r3 | Q.8 | 16:50:13.229 | 201 | 73 | 3173 | 10+20 | echoed | |
| 29 | Q-S.2 r3 | Q.9 | 16:50:13.328 | 201 | 114 | 131933 | 1000 | echoed | |
| 30 | Q-S.3 a | Q.4 | 16:50:13.500 | 201 | 74 | 2063 | 20 | echoed | |
| 31 | Q-S.3 b | Q.4 | 16:50:13.607 | 201 | 90 | 2063 | 20 | echoed | result string identical to #30 (1312 chars) |
| 32 | Q-S.4 | Q.1 | 16:50:13.737 | 201 | 71 | 1497 | 10 | echoed (same id as #31) | — returns the Q.1 result, not #31's |
| 33 | Q-S.5 | Q.1 | 16:50:13.837 | 201 | 126 | 486 | **empty** | none sent → zero GUID returned | `result` = `""` |
| 34 | Q-S.6 | Q.1 | 16:50:14.088 | 201 | 224 | 1497 | 10 | echoed | parallel |
| 35 | Q-S.6 | Q.2 | 16:50:14.103 | 201 | 181 | 651 | 1 | echoed | parallel |
| 36 | Q-S.6 | Q.3 | 16:50:14.117 | 201 | 123 | 903 | 5 | echoed | parallel |
| 37 | Q-S.6 | Q.4 | 16:50:14.129 | 201 | 104 | 2063 | 20 | echoed | parallel |
| 38 | Q-S.6 | Q.5 | 16:50:14.148 | 201 | 114 | 14272 | 99 | echoed | parallel; wall time of all 5: 345 ms |
| 39 | Q-S.7 | Q.1 | 16:55:26.817 | 201 | 359 | 1497 | 10 | echoed | after 300 s idle |
| 40 | Q-S.8 | Q.1 | 17:05:27.283 | 201 | 443 | 1497 | 10 | echoed | after 600 s idle |
| 41 | Q-S.8 | Q.4 | 17:05:27.768 | 201 | 287 | 2063 | 20 | echoed | |
| 42 | Q-S.9 before | Q.1 | 17:05:33.823 | 201 | 241 | 1497 | 10 | echoed | |
| 43 | Q-S.9 after | Q.1 | 17:06:35.599 | 201 | 189 | 1506 | 10 | echoed | change visible (+9 B), see below |
| 44 | Q-S.9 restore | Q.1 | 17:06:59.873 | 201 | 229 | 1497 | 10 | echoed | result string identical to #42 |
| 45 | Q-S.10 | `{"tables":[{"table":"NoSuchTable","fields":["Code"],"top":1}]}` | 17:07:00.217 | 400 | 226 | 148 | — | not returned | `Application_DialogException: Table NoSuchTable was not found.` |
| 46 | Q-S.10 next | Q.1 | 17:07:00.485 | 201 | 202 | 1497 | 10 | echoed | |
| 47 | Q-S.11 | Q.9 | 17:07:00.734 | 201 | 175 | 131933 | 1000 | echoed | |
| 48 | Q-S.11 | Q.9 | 17:07:00.951 | 201 | 154 | 131933 | 1000 | echoed | |
| 49 | Q-S.11 | Q.9 | 17:07:01.158 | 201 | 159 | 131933 | 1000 | echoed | |
| 50 | R.1 | Q.1 | 17:11:09.750 | 404 | 205 | 373 | — | — | `BadRequest_NotFound: No HTTP resource was found that matches the request URI '…/api/aproda/bcDataAccess/v1.0/companies(<c>)/dataRequests?tenant=<internal>&aid=FIN'.` |
| 51 | R.1 | Q.1 | 17:11:15.012 | 404 | 116 | 373 | — | — | same |
| 52 | R.1 | Q.1 | 17:11:20.157 | 201 | 198 | 1497 | 10 | echoed | ready |
| 53 | R.2 | Q.1 | 17:11:28.083 | 201 | 206 | 1497 | 10 | echoed | |

**Q-S.9 detail.** Florian changed *Payment Terms 21TAGE → Description* from empty to `E012 TEST` in the web client, and back. The API showed the new value on the first call after the save (#43) and the original state on the first call after the restore (#44). Results are live; no caching.

**Q-S.12 summary (rows 2–49)**

| Metric | Value |
|---|---|
| Requests | 48 (sequential 43, parallel 5) |
| Wall time | 16:50:08 → 17:07:01 = **16 min 53 s** (incl. 15 min of idle) |
| Status | 201 × 47, 400 × 1 (intended unknown table); **0 × 404, 0 × 429, 0 × 5xx** |
| Empty `result` | 1 (Q-S.5, no `id` — intended) |
| Latency | min 59 ms · **p50 143 ms** · **p95 410 ms** · max 615 ms · mean 167 ms |
| Latency per query (median) | Q.1 202 · Q.2 147 · Q.3 92 · Q.4 104 · Q.5 114 · Q.6 127 · Q.7 125 · Q.8 81 · Q.9 154 ms |
| Warm-up | the first call of each query in the burst is the slowest (Q.4 615 → 151 → 69 ms; Q.9 410 → 149 → 114 ms); after idle 5/10 min the first call takes 359 / 443 ms (warm ≈ 70–200 ms) |
| Bytes | 940 402 total; Q.9 always 131 933 B (stable) |
| Burst Q-S.2 | 27 requests in 4.0 s (sum of request times), no error |
| Parallel Q-S.6 | 5 at once, all 201, 104–224 ms each, 345 ms wall |

## 5. Guard code

Final functions — `I:\Florian Köll\_e012-scratch\bc-guard.ps1` (`Invoke-Bc` and `$AutoApi` from `bc-lib.ps1`; the token is read from the token file there and never printed).

```powershell
$script:Company = 'e276d4c8-e459-f111-a820-7ced8d437289'
$script:OurAppId = 'ab23bc15-d3c6-4fc6-b5bb-28c447bf8b6e'
$script:OurName = 'Aproda BC Data Access (prototype)'
$script:OurPublisher = 'Aproda AG'

function Assert-OurPackage {
    param([Parameter(Mandatory)][string]$PackageId)
    if ($PackageId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw "GUARD: '$PackageId' is not a GUID - no call" }
    $r = Invoke-Bc -Uri "$script:AutoApi/companies($script:Company)/extensions($PackageId)"
    if ($r.Status -ne 200) { throw "GUARD: lookup of package $PackageId returned HTTP $($r.Status) - no call" }
    $e = $r.Json
    $fails = @()
    if ($e.id -ne $script:OurAppId) { $fails += "id='$($e.id)'" }
    if ($e.displayName -cne $script:OurName) { $fails += "displayName='$($e.displayName)'" }
    if ($e.publisher -cne $script:OurPublisher) { $fails += "publisher='$($e.publisher)'" }
    if ("$($e.publishedAs)".Trim() -ne 'PTE') { $fails += "publishedAs='$("$($e.publishedAs)".Trim())'" }
    if ($fails) { throw "GUARD: package $PackageId is not ours ($($fails -join ', ')) - no call" }
    $e
}

function Get-OurPackages {
    $r = Invoke-Bc -Uri "$script:AutoApi/companies($script:Company)/extensions?`$filter=id eq $script:OurAppId"
    if ($r.Status -ne 200) { throw "Get-OurPackages: HTTP $($r.Status) $($r.Raw)" }
    foreach ($row in @($r.Json.value)) {
        $e = Assert-OurPackage -PackageId $row.packageId
        [pscustomobject]@{
            packageId   = $e.packageId
            version     = '{0}.{1}.{2}.{3}' -f $e.versionMajor, $e.versionMinor, $e.versionBuild, $e.versionRevision
            isInstalled = [bool]$e.isInstalled
        }
    }
}

# Lifecycle actions: only ever on a packageId that passed the guard in the same step.
function Invoke-OurPackageAction {
    param([Parameter(Mandatory)][string]$PackageId,
          [Parameter(Mandatory)][ValidateSet('uninstall', 'uninstallAndDeleteExtensionData', 'unpublish')][string]$Action)
    $null = Assert-OurPackage -PackageId $PackageId
    Invoke-Bc -Method POST -Uri "$script:AutoApi/companies($script:Company)/extensions($PackageId)/Microsoft.NAV.$Action"
}

function Wait-OurPackageUninstalled {
    param([Parameter(Mandatory)][string]$PackageId, [int]$TimeoutSec = 300)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep 2
        $r = Invoke-Bc -Uri "$script:AutoApi/companies($script:Company)/extensions($PackageId)"
        if ($r.Status -eq 404) { return [pscustomobject]@{ Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); State = 'gone' } }
        if ($r.Status -eq 200 -and -not $r.Json.isInstalled) { return [pscustomobject]@{ Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); State = 'uninstalled' } }
    } while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec)
    throw "Wait-OurPackageUninstalled: timeout after $TimeoutSec s"
}

# Ensure clean: uninstall (optionally deleting data) every installed package, then unpublish every package. 404 tolerated.
function Invoke-EnsureClean {
    param([switch]$DeleteData)
    $uninstallAction = if ($DeleteData) { 'uninstallAndDeleteExtensionData' } else { 'uninstall' }
    foreach ($p in @(Get-OurPackages | Where-Object isInstalled)) {
        $r = Invoke-OurPackageAction -PackageId $p.packageId -Action $uninstallAction
        if ($r.Status -notin 200, 204, 404) { throw "$uninstallAction $($p.packageId): HTTP $($r.Status) $($r.Raw)" }
        if ($r.Status -ne 404) { $null = Wait-OurPackageUninstalled -PackageId $p.packageId }
    }
    foreach ($p in @(Get-OurPackages)) {
        $r = Invoke-OurPackageAction -PackageId $p.packageId -Action unpublish
        if ($r.Status -notin 200, 204, 404) { throw "unpublish $($p.packageId): HTTP $($r.Status) $($r.Raw)" }
    }
    @(Get-OurPackages)
}
```

**Guard messages (C.6, lookup only — no lifecycle call was made):**

| Target | Message |
|---|---|
| *Data Administration (DA)*, PTE, publisher `Aproda AG`, installed | `GUARD: package 34ed77e8-8872-4a5d-95e7-521189da8a96 is not ours (id='f58ce9b0-c890-472c-a33b-787716435406', displayName='Data Administration (DA)') - no call` |
| *Agent Design Experience*, Microsoft, Global | `GUARD: package ab32e57e-d189-42f3-aad8-3703d31625c0 is not ours (id='00155c68-8cdd-4d60-a451-2034ad094223', displayName='Agent Design Experience', publisher='Microsoft', publishedAs='Global') - no call` |
| `not-a-guid` | `GUARD: 'not-a-guid' is not a GUID - no call` |
| our unpublished package (C.7 pre-check) | `GUARD: lookup of package 165c394c-bd98-4e60-b4f9-8d1777b629da returned HTTP 404 - no call` |

Other scratch scripts of this run (no secrets): `bc-session.ps1` (query pool + shape-only log `Send-DaRequest`), `Run3-InstallReady.ps1` (install + deployment poll + readiness loop), `Run3-SessionA.ps1` (Q-S.1–Q-S.6), `Run3-CleanDelete.ps1` (C.1–C.5 through the guard), `run3-session-log.csv` (shape-only request log).

## 6. Limits & gaps

1. **Data deletion not observable.** The prototype's only table (`Data Request DA APD`) is `TableType = Temporary`, so the app has no SQL table and `uninstallAndDeleteExtensionData` had nothing to delete. The run proves the call, its parameters (none), its status and timing — not the deletion effect. Equivalent to sync mode *Clean* only by documentation.
2. **C.7 needed an exception to rule §3.3.** The guard (correctly) refuses an unpublished package because its lookup returns 404. The raw call was made once, with Florian's approval, only to record the 404 text. In the skill, the guard's 404 means "already clean" — no call needed.
3. **Readiness** observed twice only (0 s and 10.7 s); run 2 had at least one 404 without retry. The 3-min cap in §1 is a margin, not a measured maximum.
4. **Install duration varies**: 123 s and 93 s (run 2: 56 s ×2).
5. **Token lifetime** was 73.2 min this time (run 2: 84.3 min). The re-login rule (Q-14) should use the token's `exp` claim, not a fixed 84 min.
6. **Session length** 16 min 53 s instead of the ~20 min in the brief; idle tested up to 10 min. Parallelism tested with 5 only — no throttling limit was reached, so the real limit is unknown.
7. **The guard requires `publishedAs = PTE`**: a Dev-published copy (`al_publish`, run 2 §8a) would be refused and could not be cleaned by the skill. Intended for Automation-API-only (Q-13); extend explicitly if Dev publishing is ever allowed.
8. `Invoke-EnsureClean` was executed only as a no-op on the empty state (D.1); C.1–C.5 and R.3 used the same building blocks step by step (`Run3-CleanDelete.ps1`).
9. `extensionDeploymentStatus` rows for uninstall / delete-data were not inspected.
10. Same as run 2: built against 28.3 symbols (target `application` 25.4); `extensionUpload` is deprecated (removal planned 2027 wave 1); telemetry not read back; non-admin user not tested.

## 7. State in the customer environment

**Prototype uninstalled (with data deletion) and unpublished.** `GET …/extensions?$filter=id eq ab23bc15-…` returns an empty list (17:11:46); tenant total 86 extensions — same as before the run. The package `165c394c-…` (1.0.1.0) was published twice (L, R) and unpublished twice; its binary may remain in the tenant application storage (run-2 §8a). **Payment Terms 21TAGE → Description** was changed by Florian for Q-S.9 and restored by him; the API result after the restore is byte-identical to the one before the change. No other extension and no other data were touched. Only the sandbox `Develop_Integration_TogaFood` was called.

## 8. Data check

No personal data and no secret in this report or in any file created by the run. Token file `%TEMP%\e012\token.txt` (and the temporary Q-S.9 comparison file in the same folder) deleted at 17:11. Values recorded are limited to payment-term codes (§2/§4 shapes), app names / ids / versions, company GUIDs, error texts, and the test value `E012 TEST`. The internal BC tenant name in the 404 URI is replaced by `<internal>`. The scratch folder `I:\Florian Köll\_e012-scratch\` (source, `.alpackages`, `out\*.app`, scripts, shape-only CSV log — no tokens) is kept as input for the fork. In this repo only this report was added by the run.
