# Troubleshooting — BC Data Access

Messages of the library start with `BCDA:`. Business Central texts are quoted verbatim from the E-012 live runs.

## Sign-in

| Message | Cause | Fix |
|---|---|---|
| `BCDA: LOGIN_TIMEOUT no sign-in within 300 s` | browser not completed, or the browser did not open | run `Connect-BcDataAccess` again; check that a browser window opened |
| `BCDA: LOGIN_ERROR access_denied …` / `AADSTS…` | sign-in cancelled, Conditional Access, or the account has no access to the tenant | sign in with the account that has (GDAP) access to the customer; read the `AADSTS` code |
| `BCDA: LOGIN_ERROR state mismatch` | a stale browser tab answered | close old sign-in tabs and run again |
| `BCDA: TOKEN_EXPIRED …` | the token lasts ≈ 70–85 min | run `Connect-BcDataAccess` again; session and app stay |
| `BCDA: UNAUTHORIZED …` (HTTP 401) | token refused (wrong tenant, revoked) | `Connect-BcDataAccess` again with the right tenant |
| `BCDA: SESSION_OPEN …` | a session for another tenant/environment/company is still open | `Stop-BcDataAccessSession` first |
| Interactive Windows login hangs (other tools) | broker without a window | this skill uses the system browser; as last fallback `-DeviceCode` |

## Install and clean-up

| Message | Cause | Fix |
|---|---|---|
| `BCDA: NOT_ACKNOWLEDGED …` | `-Acknowledged` missing | show the acknowledgement (SKILL.md §5), wait for yes |
| `BCDA: ASSET_HASH_MISMATCH …` | the `.app` in `assets/` does not match `app-manifest.json` | do not upload; re-sync the Aproda layer (`skill-aproda-aldc`) |
| `BCDA: INSTALL_FAILED extensionUpload HTTP 403 …` | the account may not manage extensions | ask for *D365 EXTENSION MGT* / BC admin role in that environment |
| `BCDA: INSTALL_FAILED deployment status Failed: …` | install failed in BC; the status text names the reason (e.g. object ID or name already used by another extension, platform too old — minimum BC 25.4) | read the status text; ID range 91050–91099 must be free in the tenant |
| `BCDA: INSTALL_TIMEOUT …` | deployment not `Completed` within 10 min (measured 56–123 s) | `Get-BcDataAccessState`, then `Stop-BcDataAccessSession`; retry later |
| `BCDA: API_NOT_FOUND …` | the API route is not registered yet after install (measured up to 11 s), or the app is not installed | the library retries 3 min; otherwise `Start-BcDataAccessSession` again |
| `BCDA: REUSE …` | an earlier session left the app installed | fine; tell the human (in production: confirm before querying) |
| `BCDA: GUARD … is not ours (…) - no call` | a package under the app id does not match id/name/publisher/PTE — e.g. a copy published from VS Code (`publishedAs = Dev`) | **stop**; tell the human; a Dev copy is removed manually in *Extension Management* |
| `BCDA: CLEANUP_FAILED …` / `CLEANUP_INCOMPLETE …` | uninstall/unpublish refused | `Get-BcDataAccessState`; retry `Stop-BcDataAccessSession`; else remove in *Extension Management* |
| `BadRequest_ResourceNotFound: Resource not found for the segment 'extensions'.` | the package is already gone | tolerated by the library |
| `BadRequest_NotSupported: Field 'name' is not filterable` | `extensionDeploymentStatus` cannot be filtered server-side | the library filters client-side |
| Partner access refused / environment not listed | the customer disabled partner (GDAP) access for this environment | the customer's admin enables partner access in the BC admin center |

## Queries

| Business Central text (in `BCDA: QUERY_ERROR …`) | Fix |
|---|---|
| `Table <x> was not found.` | use the AL object name (`"G/L Account"`) or the number |
| `Field <x> was not found in table <t>.` | exact AL field name (`"No."`); look it up via the `Field` recipe |
| `Field <x> in table <t> is a FlowFilter and cannot be returned.` | remove the FlowFilter field |
| `The request is not valid JSON or has no "tables" array.` | fix the JSON |
| `The "fields" array is required for table <t>.` | add `fields` |
| `Each filter needs a "field" and a "filter" value (table <t>).` | fix the filter object |
| `You do not have permission to read table <t>.` | the signed-in account lacks read permission |
| `BadRequest_MethodNotAllowed: Entity does not support modifying data.` / `Entity does not support delete.` | the API is read-only by design |
| `BCDA: EMPTY_RESULT …` | should not happen (the library always sends `id`); report it |
