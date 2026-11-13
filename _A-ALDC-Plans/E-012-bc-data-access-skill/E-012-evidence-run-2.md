# E-012 — Evidence report, run 2 (custom data-access app: Entra token + Automation API + API page)

## 1. Result and decision proposals

| Item | Result | Proposal |
|---|---|---|
| **M-4 Auth** | **Works.** Browser login with authorization code + PKCE and a localhost `HttpListener` as GDAP partner: 16 s, no device code. No consent prompt, no error. Token for `https://api.businesscentral.dynamics.com`, `scp = Financials.ReadWrite.All`, lifetime 84 min, refresh token issued. A.3/A.4 not needed. | Adopt public client `1950a258-227b-4e31-a9cf-717495945fc2` and the loopback flow as the skill's default. Token lifetime of about 84 min covers a session; re-login when it expires. |
| **M-6 Lifecycle** | **Works** via Automation API (upload → install, uninstall, unpublish). Install (upload → `Completed`) took 56 s, uninstall 4 s, unpublish 1.4 s per package. Same version 1.0.0.2 re-published after unpublish: allowed. In-place upgrade (1.0.0.0 → .1 → .2) works, but **each upgrade leaves the older package published (not installed)**. | Skill's "ensure clean" must list **all** packages by app id and unpublish each one. Uninstall and unpublish of a missing package return 404 `BadRequest_ResourceNotFound` and must be tolerated. After install the API route can return 404 for a short time (see §8). |
| **M-7 Conflicts** | **No conflict.** ID range 91050–91099 and suffix `DA APD` installed without error on a tenant with 86 extensions (82 Global, 3 PTE, 1 Dev); no extension name contains `DA APD`. | Keep 91050–91099 / `DA APD`. |
| **Read capability** | **Covers the support cases.** PTE table, table-extension fields, filters, FlowField, system tables, multi-table, 1000-row cap, error texts and write refusal all behave as specified. The API can also look up metadata itself (`Field`, `Report Selections`). Two findings: (a) the POST body **must contain a client-supplied `id` GUID**, otherwise `OnInsertRecord` does not run and the response is `201` with an empty `result`; (b) `AddLoadFields` rejects FlowFields (fixed in prototype 1.0.0.2). | Put both findings into the skill (request template always carries `id`). Add the page-level readiness retry. |

Q.12 (real support question, answered only through this API): in 2 requests — see §6.

## 2. Header

| | |
|---|---|
| Date | 2026-11-13, 16:03–16:20 (CET) |
| VS Code / harness / shell | 1.144.0 / Copilot Local, agent mode / PowerShell 7.6.9 |
| AL extension / compiler | `ms-dynamics-smb.al-18.1.2842859`, built through the `al-mcp` server (`altool`) |
| Account type | Florian, GDAP partner (signed in himself) |
| Tenant | `7391b259-9b54-46a9-9722-2d25eb4469ed` |
| Environment | `Develop_Integration_TogaFood` (Sandbox, BC 28) |
| Company | Toga Food AG (display name *TOGA FOOD SA*), id `e276d4c8-e459-f111-a820-7ced8d437289` (other company: *Gustav Gerig*, `14c13f57-b5c7-f011-8542-6045bd2a4880`) |
| App id | `ab23bc15-d3c6-4fc6-b5bb-28c447bf8b6e` |
| Acknowledgements | L.0 and U.0 given by Florian at 16:07 |

## 3. Prototype

Location: `I:\Florian Köll\_e012-scratch\DA-APD\` (outside every git repo). Built against BC **28.3** symbols (not 25.4).

| File | Object |
|---|---|
| `app.json` | `Aproda BC Data Access (prototype)`, publisher `Aproda AG`, platform 25.0.0.0, application 25.4.0.0, runtime 14.0, target Cloud, idRanges 91050–91099, no dependencies |
| `src/DataRequestDAAPD.Table.al` | table 91050 `Data Request DA APD` (temporary; `Id` Guid, `Result` Blob) |
| `src/DataAccessAPIDAAPD.Page.al` | page 91050 `Data Access API DA APD` (API `aproda/bcDataAccess/v1.0`, `dataRequest(s)`; fields `id`, `request` (page variable), `result`) |
| `src/DataAccessMgtDAAPD.Codeunit.al` | codeunit 91050 `Data Access Mgt DA APD` |
| `src/DAAPDExec.PermissionSet.al` | permissionset 91050 `DA APD Exec` (X on page + codeunit, assignable) |

Versions deployed: 1.0.0.0 (first build), 1.0.0.1 (`OnInsertRecord` now `exit(true)` instead of `Rec.Insert(false); exit(false)`), 1.0.0.2 (`AddLoadFields` only for `FieldClass::Normal`). Differences to the brief: `ProcessRequest` wraps the work in a `[TryFunction]` so every error is logged as `DAAPD0001` and re-raised unchanged.

**Compile recipe (P.2, fork-CI input).** Package cache = `<project>\.alpackages` (copied from `Base/.alpackages`: Microsoft Application, Base Application, Business Foundation, System Application 28.3 and System 28.0 — no Aproda apps needed).
```
al-mcp  al_addproject  projectPath = <scratch>\DA-APD
al-mcp  al_build       projectPath = <scratch>\DA-APD   outputPath = <scratch>\DA-APD\out
```
Result: `Aproda AG_Aproda BC Data Access (prototype)_1.0.0.x.app` (8.3 KB), 0 errors, **0 warnings** (`al_getdiagnostics`: empty). Code analyzers were not enabled.

**Self-review (P.3)**

| Check | Result |
|---|---|
| No `Insert/Modify/Delete/Rename` on business tables | OK — the only table in the app is the temporary request table; the page does not call `Insert` |
| No `Permissions` / `InherentPermissions`, no `Commit`, no event subscriber, no other objects | OK |
| Removed: key management, timestamp/nonce/signature, `IsSandbox()` gate, system-table block | OK |
| Kept: request format, name-or-number resolution, mandatory `fields`, FlowFilter rejection, FlowField `CalcField`, Option name, `top` default/cap 1000, `ReadPermission()` | OK |
| Added: `AddLoadFields`, Blob > 64 KB → `null` + `<field>__truncated`, Media/MediaSet → `Format` | Coded; **Blob truncation and Media not exercised** by Q.1–Q.12 |
| Telemetry `DAAPD0001` / `DAAPD0002`, no record data | Coded; **not read back** from Application Insights |
| Labels `Locked = true` | OK |

## 4. Auth (M-4)

| Step | Result |
|---|---|
| A.1 | Success. Flow: authorization code + PKCE (S256), system browser (`Start-Process`), `HttpListener` on `http://localhost:<free port>/`, `prompt=select_account`, scope `https://api.businesscentral.dynamics.com/.default offline_access`. Prompts: account picker only (no consent, no MFA prompt, no Conditional Access block). No `AADSTS` error. Login to token file: **16.1 s**. |
| Claims (§3.4 only) | `aud = https://api.businesscentral.dynamics.com`, `tid = 7391b259-…-25eb4469ed`, `scp = Financials.ReadWrite.All`, `roles` empty, `appid = 1950a258-227b-4e31-a9cf-717495945fc2`, lifetime 84.3 min (`expires_in` 4755 s), refresh token returned (not stored) |
| A.2 | `GET <AutoApi>/companies` → 200, 721 ms, 955 B; two companies (names above) |
| A.3 / A.4 | Not needed |

The `Financials.ReadWrite.All` scope is enough for the Automation API (upload/install/uninstall/unpublish) and for custom API pages.

## 5. Lifecycle (L / U / R)

Base = `https://api.businesscentral.dynamics.com/v2.0/<tenant>/<environment>/api/microsoft/automation/v2.0`; `<c>` = company id.

| Step | Request | Status | Duration | Notes |
|---|---|---|---|---|
| L.1 | `GET /companies(<c>)/extensions?$filter=id eq <app>` | 200 | 371 ms | empty (clean) |
| L.2 | `GET /companies(<c>)/extensions` | 200 | 640 ms | 86 extensions, inventory below |
| L.3 | `POST /companies(<c>)/extensionUpload` `{"schedule":"Current version","schemaSyncMode":"Add"}` | 201 | 163–393 ms | returns `systemId` |
| L.4 | `PATCH /companies(<c>)/extensionUpload(<systemId>)/extensionContent` (`application/octet-stream`, `If-Match: *`) | 204 | 159–223 ms | |
| L.5 | `POST /companies(<c>)/extensionUpload(<systemId>)/Microsoft.NAV.upload` | **200** (not 204) | 2.6–3.0 s | |
| L.6 | poll `GET /companies(<c>)/extensionDeploymentStatus` every 5 s | 200 | — | `InProgress` → `Completed` after **56 s** from L.3 (runs 2 and 3; run 1 not timed, see §8). `operationType` is `Upload` for install too. |
| L.7 | `GET …/extensions?$filter=id eq <app>` | 200 | — | `isInstalled=true`, `publishedAs` ` PTE` (leading space), new `packageId` per version |
| Upgrade | L.3–L.6 with 1.0.0.1, then 1.0.0.2 over the installed version | as above | 56 s | installed version replaced; **older packages stay published, not installed** |
| U.1 | `POST …/extensions(<packageId>)/Microsoft.NAV.uninstall` | 204 | 740 ms | `isInstalled=false` after **4 s** |
| U.2 | `POST …/extensions(<packageId>)/Microsoft.NAV.unpublish` (3 packages) | 204 each | 1.4 s each | available on this environment |
| U.3 | `GET …/extensions?$filter=id eq <app>` | 200 | — | empty; total back to 86 |
| U.4 | uninstall / unpublish / GET on the missing `packageId` | **404** | 130–190 ms | `{"error":{"code":"BadRequest_ResourceNotFound","message":"Resource not found for the segment 'extensions'."}}` |
| R.1 | L.3–L.7 with the **same** `.app` (1.0.0.2) after unpublish | 201/204/200 | 56 s | re-publish of an unpublished same version allowed |
| R.2 | Q.1 | **404** | 244 ms | see §8 (not repeated) |
| R.3 | uninstall (4 s) + unpublish (1.5 s) + verify | 204 / 204 / 200 | — | app gone |

**Extension inventory (L.2)** — 86 installed, publishedAs: Global 82, PTE 3, Dev 1. Aproda/PTE apps: Aproda CRM (ASXR) 24.0, Aproda Data Exchange for KMU Starter Pack (ASDXSC) 25.0 PTE, Aproda Data Interchange (ASDX) 26.0, Aproda Document Automation (ASDC) 25.0, Aproda Finance (ASFI) 27.0, Aproda Foundation Layer (ASFL) 22.0, Aproda KMU Starter Pack (ASSC) 27.0, Aproda Mobile Data Collection (ASMD) 27.0, Aproda Print Solution (ASPS) 24.0, ASDC TableLock Test 26.0 PTE, Data Administration (DA) 24.0 PTE, Gustav Gerig AG Base 25.0 Dev. Nothing matches `*DA APD*`. (The Automation API does not return ID ranges; the install itself is the collision check.)

**Notes**
- `extensionDeploymentStatus` has no `appId`; `$filter=name eq '…'` → **400** `BadRequest_NotSupported: Field 'name' is not filterable`. Filter client-side by `name` and `startedOn`. My first poll used the filter, swallowed the 400 and showed an empty status (found and corrected during the run).
- `appVersion` in the status rows is filled; `schedule` is empty.

## 6. Query matrix

`POST <ProtoApi>/companies(<c>)/dataRequests`, body `{"id":"<new guid>","request":"<json string>"}`. Rows per table; `Bytes` = response size.

| Case | Request JSON | Status | Rows | ms | Bytes | Notes |
|---|---|---|---|---|---|---|
| Q.1 | `{"tables":[{"table":"Payment Terms","fields":["Code","Due Date Calculation","Description"],"top":10}]}` | 201 | 10 | 151 | 1497 | Codes 10TAGE, 10TAGE S, 15TAGE, 15TAGE S, 21TAGE, 30TAGE, 40 TAGE, 45TAGE, 60TAGE, 90TAGE (formulas 10D…90D) |
| Q.2 | `{"tables":[{"table":"General Company Setup","fields":["Carton Unit of Measure","Pallet Unit of Measure"],"top":1}]}` | 201 | 1 | 127 | 651 | PTE table by name; keys returned as requested |
| Q.3 | `{"tables":[{"table":"Customer","fields":["No.","Key Account Manager","Travel Region"],"top":5}]}` | 201 | 5 | 100 | 903 | table-extension fields by name work |
| Q.4 | `{"tables":[{"table":"G/L Account","filters":[{"field":"Account Type","filter":"Posting"}],"fields":["No.","Name","Balance"],"top":20}]}` | 201 (1.0.0.2) | 20 | 768 | 2063 | filter + FlowField OK (`Balance` is a JSON number). On 1.0.0.1: **400** `The field 'Balance' in the 'G/L Account' table is not valid for auto loading and cannot be passed to calls to AddLoadFields, SetLoadFields, or LoadFields.` |
| Q.5 | `{"tables":[{"table":2000000153,"fields":["Name","Publisher","Version Major","Version Minor","Published As"],"top":200}]}` | 201 | 99 | 284 | 14272 | system table by number; app list matches the Automation API inventory (plus the prototype itself) |
| Q.6 | `{"tables":[{"table":2000000120,"fields":["User Security ID"],"top":1000}]}` | 201 | 57 | 152 | 4281 | row count only |
| Q.7 | `{"tables":[{"table":2000000053,"fields":["Role ID","Company Name"],"top":1000}]}` | 201 | 151 | 135 | 10030 | row count only |
| Q.8 | Q.1 table + Q.4 table in one request | 201 (1.0.0.2) | 10 + 20 | 82 | 3173 | on 1.0.0.1: same 400 as Q.4 |
| Q.9 | `{"tables":[{"table":17,"fields":["Entry No.","G/L Account No.","Posting Date","Amount","Document No."],"top":1000}]}` | 201 | 1000 | 292 | 131933 | at the cap; about 132 B/row for 5 fields |
| Q.10a | unknown table `NoSuchTable` | 400 | — | 242 | 148 | `Table NoSuchTable was not found.` |
| Q.10b | unknown field | 400 | — | 150 | 171 | `Field NoSuchField was not found in table Payment Terms.` |
| Q.10c | FlowFilter `Date Filter` on G/L Account | 400 | — | 142 | 194 | `Field Date Filter in table G/L Account is a FlowFilter and cannot be returned.` |
| Q.10d | `not json` | 400 | — | 142 | 173 | `The request is not valid JSON or has no "tables" array.` |
| Q.10e | missing `fields` | 400 | — | 191 | 173 | `The "fields" array is required for table Payment Terms.` |
| Q.10f | `{"foo":1}` | 400 | — | 165 | 173 | same text as 10d |
| Q.10g | filter without `filter` value | 400 | — | 143 | 189 | `Each filter needs a "field" and a "filter" value (table G/L Account).` |
| Q.11 | `PATCH …/dataRequests(<guid>)` | **405** | — | 136 | — | `BadRequest_MethodNotAllowed: Entity does not support modifying data.` |
| Q.11 | `DELETE …/dataRequests(<guid>)` | **400** | — | 178 | — | `BadRequest: Entity does not support delete.` |
| Q.12a | `Field` (2000000041) filtered `TableNo = 77`, fields `No.`, `FieldName`, `Class` | 201 | 23 | 75 | 2281 | the API reads its own metadata: names + class (FlowField vs Normal) |
| Q.12b | `{"tables":[{"table":"Report Selections","fields":["Usage","Sequence","Report ID","Report Caption","Report Layout Name","Report Layout Caption","Use for Email Attachment","Use for Email Body"],"top":1000}]}` | 201 | 57 | 416 | 13737 | answer below |

Lookup `NAV App Installed App` field names: `Field` table filtered `TableNo = 2000000153` (21 rows, 75–723 ms).

**Q.12 answer** (*Which report is set up in Report Selections for posted sales invoice?*): usage **`S.Invoice`** has two lines — sequence 2: report **50043** "Sales - Invoice" (custom, Gustav range), sequence 3: report **11510** "Swiss QR-Bill". No layout override on either line. Method: list the usage values (57 rows, one request), then read the `S.Invoice` rows. The caption "Verkauf - Rechnung" is not a valid filter value; the enum name `S.Invoice` is.

**Usefulness.** Name lookup, FlowFields, option names, table extensions and system tables all work; one request is enough for typical setup questions. Missing for RCA: aggregation (`CalcSums`/group by), sorting/`SetCurrentKey`, no paging beyond `top` 1000 (no offset), no filter on FlowFields by name check, and the 1000-row cap hits ledger tables (Q.9 = 132 KB per 1000 rows).

## 7. Working scripts

Full scripts are in the scratch folder: `Get-BcToken.ps1`, `bc-lib.ps1`, `bc-query.ps1`, `Install-DaApp.ps1`. Core snippets (placeholders in `<>`):

```powershell
# A.1 — authorize URL (browser), then redeem the code at /token
$authUrl = "https://login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize?client_id=<client id>&response_type=code" +
  "&redirect_uri=$([uri]::EscapeDataString('http://localhost:<port>/'))&response_mode=query" +
  "&scope=$([uri]::EscapeDataString('https://api.businesscentral.dynamics.com/.default offline_access'))" +
  "&code_challenge=<S256 of verifier>&code_challenge_method=S256&prompt=select_account&state=<state>"
$listener = [Net.HttpListener]::new(); $listener.Prefixes.Add('http://localhost:<port>/'); $listener.Start()
Start-Process $authUrl; $ctx = $listener.GetContextAsync().Result   # read ?code= and ?state=
Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token" `
  -ContentType 'application/x-www-form-urlencoded' `
  -Body @{ client_id='<client id>'; grant_type='authorization_code'; code=$code; redirect_uri='http://localhost:<port>/'; code_verifier=$verifier; scope='https://api.businesscentral.dynamics.com/.default offline_access' }
```
```powershell
# Generic call (token read from the token file; do not echo headers)
Invoke-WebRequest -Method <m> -Uri <uri> -Headers @{ Authorization = "Bearer $token" } -SkipHttpErrorCheck [-ContentType ...] [-Body ...|-InFile <app>]

# L.3–L.6 (install)
POST   <AutoApi>/companies(<c>)/extensionUpload                         {"schedule":"Current version","schemaSyncMode":"Add"}   -> systemId (201)
PATCH  <AutoApi>/companies(<c>)/extensionUpload(<systemId>)/extensionContent   octet-stream, If-Match: *, -InFile <app>        (204)
POST   <AutoApi>/companies(<c>)/extensionUpload(<systemId>)/Microsoft.NAV.upload                                              (200)
GET    <AutoApi>/companies(<c>)/extensionDeploymentStatus   # every 5 s; client-side: name -eq '<app name>', latest startedOn; until Completed|Failed

# Ensure clean / U
GET    <AutoApi>/companies(<c>)/extensions?$filter=id eq <app id>       # all packages (one per version)
POST   <AutoApi>/companies(<c>)/extensions(<packageId>)/Microsoft.NAV.uninstall    # 204, poll GET until isInstalled=false
POST   <AutoApi>/companies(<c>)/extensions(<packageId>)/Microsoft.NAV.unpublish    # 204; repeat for every package

# Query
POST   <ProtoApi>/companies(<c>)/dataRequests   {"id":"<new guid>","request":"{\"tables\":[...]}"}   -> .result (JSON string)
```

## 8. Limits & gaps

1. **`id` required in the POST body** — without it the API page returns 201, `id` = zero GUID, `result` = `""` and `OnInsertRecord` is not executed (so errors are not raised either; the first 4 queries and the first errors tests of 1.0.0.1 behaved this way). Not tested whether 1.0.0.0 (`Rec.Insert(false); exit(false)`) would also have worked with an `id`; the fix to `exit(true)` and the `id` were introduced together at 1.0.0.1.
2. **R.2 returned 404 directly after install** (`No HTTP resource was found that matches the request URI …/dataRequests`). In the main run the first query came about 5 min after the first install and worked. I did not retry before R.3 uninstalled the app, so the length of the API registration delay is **unknown**. The skill needs a readiness retry (e.g. `GET …/dataRequests` or a harmless Q until not 404) — to be measured in a follow-up.
3. **Install duration of the first upload (1.0.0.0) not measured** (my poll filter was wrong). Runs 2 and 3: 56 s each.
4. Not exercised: Blob > 64 KB truncation, Media/MediaSet, the `top`-less default, non-sysadmin users (the GDAP account had full rights; whether `DA APD Exec` alone is enough was not tested), telemetry read-back.
5. Built against 28.3 symbols; the target is `application` 25.4 — compile against 25.4 is the fork CI's job.
6. The Automation API `extensionUpload` is deprecated (planned removal 2027 wave 1) — out of scope, tracked in the fork plan.
7. Token file only holds the access token; the refresh token was not stored (re-login after 84 min).

## 8a. Addendum — publish through the AL MCP / Dev endpoint (`al_publish`, `altool publishapp`)

Requested after the main run (16:26–16:35). Same sandbox, same app id; app files built through `al_build` (1.0.0.2, 1.0.0.3).

| Step | Tool / request | Result |
|---|---|---|
| Publish 1.0.0.2 (the version that had been installed and unpublished through the Automation API) | `al-mcp-al_publish` `appPath`, `skipBuild=true`, `environmentType=Sandbox`, `environmentName`, `tenant`, `authentication=AAD`; 3 calls with and without `projectPath` | **Failed** each time, MCP message only `PublishFailed` (no cause). `altool publishapp` with the same arguments shows the cause: `UnprocessableEntity … Error code: 85132273 Violation of PRIMARY KEY constraint 'Tenant Application Storage$Key1'. Cannot insert duplicate key … (<packageId of 1.0.0.2>, 28.5.0.0)`. A package that was published through `extensionUpload` and unpublished again is still in the tenant's application storage, so the Dev endpoint cannot publish the identical package (same package id). The Automation API itself re-uploaded the same package without problem (R.1). |
| `al_auth_login` | Sandbox, tenant | `Authenticated. Tokens cached` (`authRequired=false`); not needed before `al_publish`, which logs in interactively on its own |
| Publish 1.0.0.3 (new package id) | `al-mcp-al_publish` as above | **Success**, message `Package published … (8270 bytes)`. Endpoint used by altool: `POST /v2.0/<environment>/dev/apps?tenant=<tenant>&SchemaUpdateMode=synchronize&DependencyPublishingOption=ignore` |
| State after publish | `GET …/extensions?$filter=id eq <app>` | `isInstalled=true`, **`publishedAs = Dev`** (not PTE); no `extensionDeploymentStatus` row is created for Dev publishes (last rows stay 1.0.0.1 / 1.0.0.2) |
| Query | Q.1 through the API page | 201, 245 ms, 3 rows, no 404 (first check ran about 1.5 min after the publish) |
| Uninstall / unpublish | Automation API, same calls as U.1/U.2 | 204 / 204; uninstall 4 s; app gone, total 86 |
| Publish 1.0.0.3 again after unpublish | `al-mcp-al_publish` | **Failed** (`PublishFailed`, no cause). Immediately afterwards `altool publishapp` with identical arguments **succeeded**. Cause of the MCP failure **not found** (no log reachable); possibly transient or MCP-specific. One of the six `al_build`/`al_publish` MCP calls of this block also failed transiently (`al_build` "CompilationFailed" with 0 diagnostics, OK on retry). |
| Q.1 on the second Dev install, uninstall, unpublish | as above | 201 / 204 / 204; app gone, total 86 |

Findings for the skill:
- `al_publish` **can publish a finished `.app`** (`appPath` + `skipBuild=true`) into a SaaS **sandbox** with browser login (no `launch.json` needed; the Dev endpoint exists for sandboxes only). It cannot install into Production.
- The result is a **Dev** extension, installed immediately for all companies; no upload, no polling, no deployment-status row. Publish time was a few seconds (not stopwatch-measured).
- Uninstall and unpublish work through the Automation API for Dev extensions (same calls, 204).
- Error output of the MCP tool is empty; `altool publishapp <app> --environmentname … --environmenttype Sandbox --tenant … --authentication AAD` gives the real text and is the better diagnostic and fallback (it uses the same cached login as the MCP tool).
- **Package-id rule:** a package that was published via `extensionUpload` and unpublished stays in `Tenant Application Storage`; publishing the identical package via the Dev endpoint then fails with the duplicate key error. Rebuild with a higher version (new package id) in that case. A package that was published via the Dev endpoint and unpublished could be published via the Dev endpoint again (altool).
- Dev extensions published from VS Code are removed when the sandbox is updated or relocated (altool message) — fine for a per-session app.

## 9. State in the customer environment

**Prototype uninstalled and unpublished** (state after the addendum, 16:35). `GET …/extensions?$filter=id eq ab23bc15-…` returns an empty list; total extensions 86 (same as before). Packages published during the run (1.0.0.0, 1.0.0.1, 1.0.0.2 ×2 via Automation API; 1.0.0.3 ×2 via Dev endpoint) were all unpublished. Package binaries of unpublished versions may remain in the tenant application storage (see §8a). No other extension was touched. No other environment was called. Only the sandbox `Develop_Integration_TogaFood` was used.

## 10. Data check

No personal data and no secret in this report or in any file created by the run. Token file `%TEMP%\e012\token.txt` deleted. Values recorded are limited to payment-term codes, app names/versions, report ids/captions from the Report Selections setup table, company names and GUIDs of the environment. The scratch folder `I:\Florian Köll\_e012-scratch\` (source, `.alpackages` copy, `out\*.app`, helper scripts — no tokens) is kept as input for the fork. In this repo only this report was added by the run; `git status` also shows pre-existing changes (`Base/.vscode/launch.json`, `Base/app.json`, deleted `Base/.vscode/mcp.json`, `.github/documentation/ALDC/`, earlier files in `_e2e-tests/`) that were not touched.
