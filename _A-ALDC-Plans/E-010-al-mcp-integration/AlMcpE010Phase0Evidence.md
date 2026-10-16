# E-010 Phase-0 Evidence: AL MCP / AL Tool Integration

**Measurement date:** 2026-10-15  
**Status:** In progress; recorded observations are reproducible and secret-free.  
**AL CLI:** `18.1.43.24897+799e32e9b48e151929e79fa662a5ddd4a2d4ebce`

## Safety Boundary

The measurements use only the two user-approved shared development targets:

| Target | Transport | Authentication | Tenant | Test company |
|---|---|---|---|---|
| `TOGA_FOOD_SA_28_AG_28_CH_FKO` | ASINST, HTTP port 9540 | Windows | `default` | `CRONUS (Schweiz) AG` |
| `flobi-wan-kenobi-gustavgerig-dev-deployment` | Fkh, HTTPS port 7049 | UserPassword via current-user DPAPI store | `default` | `CRONUS CH` |

No password, authorization header, or credential value is recorded. Fkh credentials were materialized only in the short-lived child process that ran the command. No `ForceSync`, `Recreate`, or `forceUpgrade` operation was used in Phase 0.

## Scope Snapshot

ASINST service `TOGA_FOOD_SA_28_AG_28_CH_FKO` was running at BC `28.0.50938.0`. Its relevant packages were all Tenant scope:

| App | Version | Installed | Sync state |
|---|---:|---:|---|
| Gustav Gerig AG Base | `25.0.0.156` | No | `NotSynced` |
| Gustav Gerig AG Base | `25.0.0.158` | Yes | `Synced` |
| Gustav Gerig AG Base Test | `25.0.0.58` | Yes | `Synced` |

The old `25.0.0.156` Base package remains published but inactive. It is an observable recovery artifact and must not be removed as part of this evidence campaign.

## C-5: Current JSONC Parsing

On PowerShell `7.6.6`, `ConvertFrom-Json` successfully parsed the actual `Base/.vscode/launch.json`, which contains both line comments and a trailing comma:

```json
{
  "PowerShellVersion": "7.6.6",
  "ConvertFromJsonSucceeded": true,
  "Error": ""
}
```

Conclusion: a PowerShell 7 local-target resolver can parse the current `launch.json` directly. This is workstation evidence, not a compatibility promise for Windows PowerShell 5.1.

## Q-13a: AL CLI Test Groups Versus DRV

### AL CLI group containing 59010 through 59013

The following test-groups payload was supplied to `altool runtests --testgroups` on both targets:

```json
[
  { "codeunitId": 59010 },
  { "codeunitId": 59011 },
  { "codeunitId": 59012 },
  { "codeunitId": 59013 }
]
```

Both connections succeeded. In both cases the tool executed only codeunit `59010`, returned `13 passed, 0 failed, 0 skipped`, then emitted `A task was canceled.` The final structured result nevertheless reported `succeeded: true` and `data.success: true`.

| Target | Observed result | Interpretation |
|---|---|---|
| ASINST | `59010`: 13 passed; cancellation after the first group | The requested four-codeunit range was not completed. |
| Fkh | `59010`: 13 passed; cancellation after the first group | Same behavior over the UserPassword/Fkh transport. |

Source inspection explains a strong candidate for the cancellation: `59011` is a setup codeunit and `59012` is a manual-events codeunit, while `59010` and `59013` are test codeunits. A follow-up group containing only actual test codeunits is required to distinguish non-test handling from a multi-group CLI defect.

### AL CLI group containing only test codeunits

The follow-up payload contains `59010` and `59013` only. It completed both groups successfully on both targets:

| Target | Result | Process wall-clock duration | Diagnostic noise |
|---|---:|---:|---|
| ASINST | 25 passed, 0 failed, 0 skipped | 10,807 ms | `A task was canceled.` was still emitted before the successful JSON result. |
| Fkh | 25 passed, 0 failed, 0 skipped | 3,848 ms | An `Index was out of range ... chunkLength` message was emitted before the successful JSON result. |

The result array named both codeunits and contained 25 entries. The CLI therefore supports several valid test-codeunit group entries in one authenticated session. The extra blank method entries are framework completion records. They account for the apparent difference from the DRV XUnit total, which counts 23 test cases for the same numeric range.

### DRV web-client runner

The DRV public entry point cannot run tests only: its `skipbuild` mode still deploys. For this measurement the existing `Resolve-DeployRunVerifyConfig` and `Invoke-DeployRunVerifyRun` functions were invoked directly with a temporary runner-only configuration. This did not call build or deployment functions.

| Target | Range | Result | Wall-clock duration |
|---|---|---:|---:|
| ASINST | `59010..59013` | 23 passed, 0 failed | 45,896 ms |
| Fkh | `59010..59013` | 23 passed, 0 failed | 15,673 ms |

The Fkh runner used the four client DLLs extracted from the live target container. The test execution itself took 3.493 seconds; the measured runner wall-clock includes initialization, connection, execution, result-file generation, and summary serialization.

The pre-fix engine's strict version gate rejected this source because the target reports `28.3.52162.53362`, while its own `Microsoft.Dynamics.Framework.UI.Client.dll` reports `28.0.53322.0`. The CH 28.0 through 28.6 product-DVD client DLLs likewise report `28.0.*`; therefore an exact major/minor comparison is unsatisfiable for a BC 28.3 target. The first measurement used an in-memory major-only override solely to establish runner viability. The corrected engine is independently validated below.

This proves that the Fkh web-client runner, UserPassword credential flow, company selection, XUnit result generation, and the requested numeric range work against the live target.

### Preliminary conclusion

The DRV runner is the only measured route that accepts the literal numeric range and produces XUnit XML. `altool runtests --testgroups` is a viable faster grouped-test route for actual test codeunits, but it has no numeric-range semantics: setup or helper codeunits must be filtered before invocation. Callers must verify that every requested test codeunit appears in `data.results`; neither a zero process exit code nor `data.success: true` alone proves test completeness.

### B-1: Live client-DLL version-gate validation after the engine fix

The hand-updated engine now exposes `ConvertTo-DeployRunVerifyMajor`, compares only the DLL and target major versions, logs the full DLL and target versions on acceptance, and no longer contains the stale `-GlueFrom` recovery hint. The requested runner-only checks used the existing temporary configurations for `59010..59013`. They did not build or deploy either app.

| Target | Configuration | Result |
|---|---|---|
| Fkh BC `28.3.52162.53362` | `UserPassword`, target-derived client DLL source, no in-memory override | `23 passed, 0 failed` in 110,211 ms. The log reported `Runner client DLL 28.0.53322.0+... accepted for target BC 28.3.52162.53362 (major match)`. |
| ASINST BC `28.0.50938.0` | `Windows`, runner `28.0` | `23 passed, 0 failed` in 14,913 ms. The log reported `Runner client DLL 28.0.50938.0+... accepted for target BC 28.0.50938.0 (major match)`. |

The B-1 fix is live-validated for both the Fkh minor-mismatch case and the ASINST 28.0 regression case. The folder convention remains `<runnerDir>/<target major.minor>`: `28.3` legitimately contains a client DLL whose version begins `28.0`.

### B-2: Missing authentication live-resolution validation after the engine fix

An ignored scratch configuration selected an ignored `launch.json` configuration that supplied server, instance, scheme, tenant, and company but deliberately omitted `authentication`. `Resolve-DeployRunVerifyConfig` threw before any connection attempt:

```text
authentication is not set — set it explicitly in launch.json configuration
'E010 no authentication' or <scratch config path>. Supported: Windows, UserPassword.
```

The B-2 missing-value path is therefore validated as fail-fast with no connection. Source inspection also confirms explicit `AAD` and `MicrosoftEntraID` produce a named unsupported-authentication stop, while other values produce a named unknown-authentication stop; those optional variants were not executed against a target because they are resolver-only paths.

## Q-13b: Raw CLI Result Shapes

| Case | Process exit | Structured result | Interpretation |
|---|---:|---|---|
| Green actual-test group (`59010`, `59013`) | 0 | `succeeded: true`, `data.success: true`, `total: 25` | Valid success once the requested IDs are confirmed in the result array. |
| Non-test group (`59011`) | 0 | `succeeded: true`, `data.success: true`, `total: 0`, `results: []` | No validation error is raised. A caller that checks only success would incorrectly accept an empty test run. |
| Wrong port (`1`) | 1 | `succeeded: false`, `errorDetails.code: UnknownError`, `retryable: true` | Connection refusal during metadata discovery is correctly surfaced as a non-zero invocation failure. |

No existing, reproducible red test was deliberately created or induced. Phase 0 does not modify product code or shared test data merely to produce an error. Therefore the red-result JSON and the Q-9 diagnostic comparison remain blocked pending either a naturally failing test or explicit approval for a dedicated throwaway test app.

## Q-13c: AL CLI Publish and Exact-Package Retry

A fresh local `al_build` generated `Aproda AG_Gustav Gerig AG Base_25.0.0.158.app`. The package was published with explicit target parameters and `--schemaupdatemode Synchronize`; no destructive schema mode or force-upgrade flag was supplied.

| Target | Fresh package | Exact same package retry | Observed endpoint behavior |
|---|---:|---:|---|
| ASINST | Exit 0, 15,594 ms | Exit 1, 733 ms | Initial publish succeeded; retry returned HTTP `422 UnprocessableEntity`, `duplicate package ID`. |
| Fkh | Exit 0, 8,999 ms | Exit 1, 573 ms | Initial publish succeeded; retry returned HTTP `422 UnprocessableEntity`, `duplicate package ID`. |

Conclusion: a new build can be accepted with the existing app version when it carries a new package ID. The exact same package file is not idempotently re-publishable. Automation must treat HTTP 422 duplicate-package responses as an expected, non-retryable terminal state and must not assume that the package needs removal or a destructive schema operation.

## Q-2: Test Package-Cache Freshness

Before a fresh MCP Base build, Test's cached Base package was:

| Package location | Timestamp (UTC) | SHA-256 |
|---|---|---|
| `Test/.alpackages/Aproda AG_Gustav Gerig AG Base_25.0.0.158.app` | 2026-09-30 13:12:05 | `DB22B3DD...782FF25C` |

After the MCP Base build, the newly produced Base output package was 1,695,544 bytes with timestamp `2026-10-15 15:24:15 UTC` and SHA-256 `0D07F319...F4E04D62`. The Test cache still had the original timestamp, size, and hash.

Both subsequent builds succeeded:

| Route | Result | Cache state |
|---|---|---|
| MCP `al_build` for Test | Package generated successfully | Unchanged stale Base package. |
| Direct `alc.exe /project:Test /packagecachepath:Test/.alpackages` | Exit 0; output package produced | Unchanged stale Base package. |

Conclusion: neither measured MCP build route refreshes Test's Base package cache. The current source does not reference a symbol that distinguishes the two Base packages, so both Test builds are green; that does not establish cache freshness. A deployment-faithful dependency build must refresh the Base package in Test's cache, as the DRV build path does.

## Q-3: AL CLI Selection Evidence

Two different AL command-line tools are present on this workstation:

| Source | Version | Role in the current prototype |
|---|---|---|
| User .NET tools `al.exe` | `18.0.41.39415+52f9a4d9bc81f38e3c0e538ef850df882c2d2cf9` | Available in `PATH`; not selected by the MCP starter. |
| `ms-dynamics-smb.al-18.1.2842859` extension `bin\\altool.exe` | `18.1.43.24897+799e32e9b48e151929e79fa662a5ddd4a2d4ebce` | Selected by the current MCP starter. |

The current starter enumerates valid `ms-dynamics-smb.al-*` extension folders, supports `bin\\altool.exe` and `bin\\win32\\altool.exe`, then orders candidates by extension-folder `LastWriteTimeUtc` descending. It rejects a timestamp tie and never considers the separately installed `al.exe`.

Only one valid AL Language extension folder is installed, so no competing-extension selection could be measured. The timestamp behavior is therefore an observed implementation fact, not an endorsed selection policy.

Conclusion: Phase 1 must replace timestamp ordering with parsed semantic-version ordering across valid extension folders, retain both known executable layouts, and fail on an unresolvable version tie or invalid version. A synthetic multi-folder test belongs to that resolver's implementation validation; it cannot establish a behavior of the currently installed single-version environment.

## Q-5: AL MCP Tool Names and Agent Frontmatter Boundary

A read-only JSON-RPC `tools/list` request to the installed AL MCP server returned these exact tool names and casing:

```text
al_addproject
al_getdiagnostics
al_run_tests
al_build
al_writetranslation
al_inspectpage
al_getpackagedependencies
al_auth_logout
al_getnextobjectid
al_downloadsymbols
al_symbolrelations
al_symbolsearch
al_publish
al_compile
al_auth_login
al_searchtranslations
```

The repository MCP configuration registers this server as `al-mcp`. The AL MCP protocol itself returned unqualified names such as `al_build`; it did not return a VS Code custom-agent `tools:` identifier.

Existing agent frontmatter in this repository uses the documented extension-tool form `<publisher>.<extension>/<tool>`, for example `ms-dynamics-smb.al/al_symbolsearch`. No host-side resolved custom-agent tool registry is available to this session, and Q-20 establishes that an independently launched server is not equivalent to the VS Code-managed connection host. Consequently, Phase 0 cannot prove whether the VS Code host exposes this repository MCP server to custom-agent frontmatter as `al-mcp/al_build`, another qualified name, or not at all.

Conclusion: the raw MCP names above are measured and may be used by any MCP client after `tools/list`. Do not add a guessed qualified AL MCP name to custom-agent frontmatter. The remaining host-integrated measurement requires a temporary ignored agent definition, a VS Code reload, and inspection of the active Tools panel or an equivalent resolved host registry.

## Q-14: Automation API Versus ASINST Management DLL

The official Automation API documentation places its examples on the Business Central SaaS endpoint `https://api.businesscentral.dynamics.com/v2.0/{environment}/api/microsoft/automation/v2.0/...` and explicitly states: "Installing per-tenant extensions using Automation APIs is only possible in SaaS." It further marks the Automation API `extensionUpload` flow as deprecated in favor of Business Central Admin Center and its API.

A read-only Windows-authenticated `GET` to the corresponding Automation API route under the ASINST service URL returned HTTP `404 Not Found`. No ASINST state was changed.

Conclusion: the Automation API cannot replace the Management DLL route for this OnPrem ASINST target's per-tenant extension recovery. Retain the measured tenant-scoped `Get-NAVAppInfo`, `Uninstall-NAVApp`, and `Unpublish-NAVApp` path for ASINST. This conclusion is limited to extension lifecycle/recovery; it does not rule out unrelated Automation API functionality in supported SaaS environments.

## Q-18: Direct Dev Endpoint and Fkh Adapter Roles

The direct multipart Development Service publish route is already measured on both targets in Q-13c: a newly built package published successfully, while an exact package retry returned the same HTTP `422` duplicate-package result on ASINST and Fkh. This proves a common publish primitive for the two authentication/transport paths.

The installed Fkh client is `2026.819.2`. A read-only `listcontainers --all --asJson` query found exactly one matching running Gustav Gerig target with an `appLabel`, and `getappinfo --asJson` found one installed, `Synced` Gustav Gerig AG Base Test app. Fkh therefore provides a live target-discovery and app-state-inspection adapter without relying on manual endpoint construction.

### Equal-probe publish comparisons

On the running Fkh target, two separately compiled packages of the disposable `E010 Recovery Probe` app were published in sequence. Both packages had the same app ID, name, publisher, version, runtime, and one-object source; their build timestamps differed, producing distinct package IDs. Before each publish, tenant `default` was verified to have no matching probe. After each publish, `Get-NAVAppInfo -TenantSpecificProperties` reported `IsPublished=True`, `IsInstalled=True`, and `SyncState=Synced`. The probe was then uninstalled, synchronized with `Clean`, unpublished, and verified absent. The `finally` cleanup ran after the complete comparison and was also verified absent.

| Run | Direct Development Service | Fkh `publishapp` | Result |
|---|---:|---:|---|
| Initial run | 23,247 ms | 2,309 ms | Both routes published, installed, and synchronized the probe. |
| Repeat with freshly built packages | 488 ms | 2,481 ms | Both routes published, installed, and synchronized the probe. |

The Direct measurement starts immediately before `PostAsync` and excludes request construction and authentication-store retrieval. The Fkh measurement starts immediately before the external CLI invocation and includes its local CLI/backend orchestration. Neither timing includes compilation, preflight state inspection, or cleanup. The routes are lifecycle-equivalent for this probe, but their request details differ slightly: Fkh emitted `SchemaUpdateMode=synchronize&tenant=default`, while the direct request also supplied `DependencyPublishingOption=Default`. A transient Fkh Function Catalog HTTP `503` occurred before the repeat's preflight completed; neither publish had started, so that attempt is excluded from the table.

The two valid runs have opposite timing winners: the initial Fkh run completed approximately $23,247 / 2,309 \approx 10.1$ times faster, while the repeat's Direct POST completed approximately $2,481 / 488 \approx 5.1$ times faster. The sample is too small and variable to establish a performance winner. Select Fkh for its verified container discovery and deployment abstraction, and retain Direct POST as a controlled protocol and diagnostic primitive.

### Working Direct POST for a `UserPassword` Fkh target

The successful direct request was an HTTP `POST` to:

```text
https://flobi-wan-kenobi-gustavgerig-dev.switzerlandnorth.cloudapp.azure.com:7049/BC/dev/apps?SchemaUpdateMode=synchronize&DependencyPublishingOption=Default&tenant=default
```

It uses `MultipartFormDataContent` with one `StreamContent` part for the `.app` file. Its `Content-Disposition` is `form-data`, and the part name, file name, and file-name-star are the package file name. `Expect: 100-continue` is disabled and the client timeout is infinite for the publish operation.

For this UserPassword target, assigning `HttpClientHandler.Credentials` and `PreAuthenticate` alone was insufficient: the initial non-replayable multipart POST received HTTP `401`. The working representation creates the Basic authorization value only in memory from the current-user DPAPI credential, sets it as `Authorization: Basic <base64(username:password)>` before the first POST, then sends the multipart body. The measurement credential was confirmed ASCII-only; a reusable helper must retain Q-19's conservative non-ASCII rejection rule. No credential, header, or encoded value is persisted or logged.

Conclusion: retain the direct Development Service POST as the common deterministic primitive for controlled protocol automation and diagnostics, and use Fkh for verified container classification, dependency-aware Fkh deployment, and post-deployment inspection. The public AL MCP `al_publish` tool remains the preferred normal abstraction. The final Phase-1 helper boundary is an architecture decision, not a further target write required for this evidence.

## Q-1: MCP Default Target Resolution

The currently managed `al-mcp` server was started by the project-local Fkh credential launcher. It injects only child-process UserPassword credentials; it does not set `BC_SERVER_URL`, `BC_SERVER_INSTANCE`, or `BC_SERVER_PORT`.

An MCP `al_run_tests` request for codeunit `59021` supplied only `projectPath: Test` and `company: CRONUS CH`, with no server, instance, port, tenant, authentication, or environment parameters. It completed `10 passed, 0 failed, 0 skipped`.

`CRONUS CH` is unique to the Fkh target used in this campaign, so this confirms the current VS Code-managed MCP default resolved to the Fkh launch configuration in `Test/.vscode/launch.json`. This proves launch-file fallback when no `BC_SERVER_*` target variable is provided.

### `BC_SERVER_URL` precedence

With only child-scoped `BC_SERVER_URL=http://apd-svw-nst05.aproda.ch` set, and the normal Test `launch.json` still selecting Fkh, the AL CLI resolver logged:

```text
Incoming params: Server=http://apd-svw-nst05.aproda.ch, ServerInstance=(null)
Found launch.json config: ... instance=BC, auth=UserPassword
Final params: Server=http://apd-svw-nst05.aproda.ch, ServerInstance=BC,
              EnvironmentType=OnPrem, Auth=UserPassword
```

The resulting request failed with `UserNotAuthenticatedException`, as expected for the hybrid combination of ASINST host and Fkh `UserPassword` authentication. An isolated MCP server with the same single variable produced the same authenticated-operation failure. Therefore `BC_SERVER_URL` has precedence over `launch.json.server`, but it replaces only the URL: omitted `BC_SERVER_INSTANCE`, `BC_SERVER_PORT`, and authentication values still merge from the chosen launch configuration.

**Operational rule:** never set `BC_SERVER_URL` alone for a target switch. Set a complete child-process target bundle (`BC_SERVER_URL`, `BC_SERVER_INSTANCE`, `BC_SERVER_PORT`, and the matching authentication/credential context), or pass every target parameter explicitly to the MCP tool.

### Multiple launch configurations

Two temporary, ignored project configurations contained the same complete ASINST and Fkh entries, with only their array order reversed. Each parameterless `altool runtests 59021 --project <project>` call selected the first entry and completed successfully:

| `configurations[]` order | Resolver-selected target | Result |
|---|---|---|
| ASINST first, Fkh second | ASINST `TOGA_FOOD_SA_28_AG_28_CH_FKO`, Windows auth | 10 passed, 0 failed |
| Fkh first, ASINST second | Fkh `BC`, UserPassword | 10 passed, 0 failed |

The resolver logs named the first entry as `Found launch.json config`, then repeated its server, instance, and authentication in `Final params`. Thus, when no explicit target values or complete environment bundle are supplied, the first active server configuration wins. Configuration order is therefore operational behavior, not cosmetic ordering.

The manually launched `altool launchmcpserver ... --transport stdio` probe did not load either a reduced temporary project or the Base project as a connection context and returned `No server connection is configured`. The VS Code-managed MCP server does load the normal Test project configuration, as proved above. This bootstrap difference is recorded as a limitation of the stand-alone STDIO probe; it does not weaken the direct resolver evidence, but Phase 1 must not rely on an independently spawned MCP server reproducing VS Code's project-context initialization.

## Q-20: Stand-Alone Versus VS Code-Managed MCP Connection Context

The parameterless `al_run_tests` request was repeated through the exact command chain declared in `Base/.vscode/mcp.json`: `powershell.exe` content-loaded `Start-AlMcpWithFkhCredential.ps1`, which then started `altool launchmcpserver` with the Base and Test paths. It used the same Test project and `CRONUS CH` company as the successful VS Code-managed request and supplied no explicit target parameters.

The result was again `ConnectionFailed` with `No server connection is configured. Provide environmentName and tenant for cloud, or serverUrl and serverInstance for on-premise, or add a configuration to launch.json.` The launcher still supplied the Fkh credential, so the failure occurs before a UserPassword authentication attempt.

Conclusion: executing the `mcp.json` launcher command as an independent process is not equivalent to VS Code registering and managing that server. The measured difference is the VS Code MCP host context, although this experiment does not identify the specific host-to-server mechanism that supplies the connection. Phase 3 must verify the extension-registered AL MCP server in its VS Code host and must not assume a separately spawned `altool launchmcpserver` will inherit the same connection behavior.

## Q-21: Explicit Target Parameters for `al_run_tests`

A stand-alone MCP `al_run_tests` request supplied the complete ASINST target bundle:

```text
serverUrl=http://apd-svw-nst05.aproda.ch
serverInstance=TOGA_FOOD_SA_28_AG_28_CH_FKO
port=9540
authentication=Windows
tenant=default
```

With `projectPath=Test`, company `CRONUS (Schweiz) AG`, and codeunit `59021`, it completed `10 passed, 0 failed, 0 skipped`. The result named each test method and carried `codeunitId`, `methodName`, `status`, `output`, and `durationMs` in `data.results`.

Conclusion: `al_run_tests` accepts and honors the explicit on-premise target parameters. The complete-parameter variant of C-2 can therefore cover test runs as well as publish operations. As with `al_publish`, callers must provide a complete compatible target bundle and not rely on partial merge behavior.

## Q-9: Red-Test Diagnostic Detail

With explicit approval, a fixed `Error(...)` was temporarily added to the first method of codeunit `59020`, published only to the Fkh development tenant, and removed immediately after the measurements. The restored Test package was rebuilt, published with `Synchronize`, and verified by a green `59020` run (`13 passed, 0 failed`). No red package remains deployed.

### Direct `altool runtests`

The single-codeunit Fkh run returned process exit `1`, `succeeded=false`, and `errorDetails.code=TestRunFailed`. Its `data.results` contained the failing method with `codeunitId`, `methodName`, `status`, `durationMs`, and `output`. The output contained both the injected error text and the AL call stack, including codeunit, method, source line, extension, publisher, and version.

The runner continued after the failed first method and executed all remaining methods. Its aggregate result was `11 passed, 2 failed, 0 skipped`; the second failed entry had an empty `methodName`, repeated the same error output, and represented the codeunit completion record rather than a second failing test method.

### MCP `al_run_tests`

The same red codeunit was executed through `al_run_tests` with the same complete Fkh target bundle. The MCP text content enclosed the same structured result shape: `succeeded=false`, `TestRunFailed`, the failed method's error text and AL call stack in `data.results[].output`, plus the same empty-method completion record. The method and aggregate counts matched the direct CLI result (`11 passed, 2 failed, 0 skipped`).

### Mixed CLI Test Groups

A single `altool runtests --testgroups` session ran the red `59020` followed by the green `59021`. It did not stop after the first codeunit failure: `59021` completed with `10 passed, 0 failed`. The combined result was process exit `1`, `data.success=false`, and `21 passed, 2 failed, 0 skipped` across 23 result records.

Conclusion: both direct CLI and MCP carry enough per-method error text and AL call-stack detail for the DRV triage pattern. Triage code must use non-empty `methodName` failure records as the primary actionable failures and de-duplicate or ignore the empty-method completion record. A red test codeunit does not prevent later test groups in the same authenticated CLI session from running; callers must inspect aggregate success after all requested groups complete.

## Q-8: VS Code MCP Lifecycle Commands

The installed VS Code core registers the following command IDs:

| Command | Purpose |
|---|---|
| `workbench.mcp.startServer` | Start an MCP server. |
| `workbench.mcp.stopServer` | Stop an MCP server. |
| `workbench.mcp.restartServer` | Restart an MCP server. |

The commands are registered by the VS Code MCP workbench code; `mcp.startServer`, `mcp.stopServer`, and `mcp.restartServer` are separate internal agent-host RPC messages, not command-palette command IDs. Therefore MCP lifecycle control is available through VS Code and is not inherently restricted to a human clicking the UI.

This agent session has no general-purpose VS Code command invocation capability for non-workspace-creation operations, so it did not execute a lifecycle command against the active AL MCP server. The launch and restart decision must currently be made by the user or by a future explicitly exposed, scoped command tool. A stand-alone `altool launchmcpserver` remains unsuitable as a substitute because it does not reproduce VS Code-managed project connection initialization.

## Q-10: Credentialless UserPassword MCP Request

An explicit Fkh/UserPassword MCP tool request was made with no `BC_SERVER_*` credential variables and no credential injection. The JSON-RPC probe captured no inbound `elicitation/create` message or other prompt request. The tool result was an `UnknownError` wrapping `UserNotAuthenticatedException`.

Conclusion: in this measured scenario, the AL MCP server does not interactively elicit missing UserPassword credentials. A launcher must supply the UserPassword credential to its short-lived MCP child process before the request; it must not expect the server to prompt for it.

## Q-16: Tenant-Scoped Uninstall and Unpublish Recovery

A disposable `E010 Recovery Probe` app (`Aproda AG`, version `1.0.0.0`) was compiled and published to ASINST with `altool publishapp --schemaupdatemode Synchronize`. Before cleanup, tenant-specific inspection reported `Scope=Tenant`, `IsPublished=True`, `IsInstalled=True`, and `SyncState=Synced` for tenant `default`.

The following tenant-scoped recovery sequence was then run without `ClearSchema`, `DoNotSaveData`, `ForceSync`, or `Recreate`:

```powershell
Uninstall-NAVApp -ServerInstance $instance -Tenant default `
  -Name 'E010 Recovery Probe' -Publisher 'Aproda AG' -Version '1.0.0.0'
Unpublish-NAVApp -ServerInstance $instance -Tenant default `
  -Name 'E010 Recovery Probe' -Publisher 'Aproda AG' -Version '1.0.0.0'
```

| Step | Observed tenant state |
|---|---|
| After `Uninstall-NAVApp` | `IsPublished=True`, `IsInstalled=False`, `SyncState=Synced` |
| After `Unpublish-NAVApp` | Zero matching packages returned by `Get-NAVAppInfo` |

Conclusion: on the ASINST target, the tenant-scoped `Uninstall-NAVApp` then `Unpublish-NAVApp` path cleanly removes a disposable DEV app. It is suitable as the non-destructive package-identity recovery path after an intentional removal decision; it must not be used to remove the historical Base recovery artifact described in the scope snapshot.

## Q-22: `PublishedAs` on BC 28 Tenant App Information

The ASINST target was queried both without and with tenant scoping:

```powershell
$si = 'TOGA_FOOD_SA_28_AG_28_CH_FKO'
Get-NAVAppInfo -ServerInstance $si -Name 'Gustav Gerig AG Base' |
  Select-Object Name, Version, Scope
Get-NAVAppInfo -ServerInstance $si -Name 'Gustav Gerig AG Base' `
  -Tenant default -TenantSpecificProperties |
  Select-Object Name, Version, Scope, IsInstalled, SyncState
```

Both forms listed the same Tenant-scope Gustav Gerig Base versions: `25.0.0.156` and `25.0.0.158`. The non-tenant query identifies both as `Scope=Tenant`, but does not populate tenant-specific installation or synchronization state. The tenant-scoped query reported `25.0.0.156` as not installed and `NotSynced`, and `25.0.0.158` as installed and `Synced`.

The tenant-specific command returned 100 app records. Its objects exposed `AppId`, `ExtensionDataVersion`, `ExtensionType`, `IsInstalled`, `IsPublished`, `Name`, `NeedsUpgrade`, `Publisher`, `Scope`, `ServerInstance`, `SyncState`, `Tenant`, and `Version`; no record exposed `PublishedAs`.

Conclusion: B-3's proposed visibility defect is not confirmed: `Get-NAVAppInfo -Name` without `-Tenant` does list the Tenant-scope versions. `-Tenant default -TenantSpecificProperties` remains necessary when cleanup decisions need `IsInstalled` or `SyncState`. Separately, on this BC 28 Management-cmdlet surface, `PublishedAs` cannot distinguish a tenant version published through the Management DLL from a DEV Endpoint package because the property is absent. Cleanup or recovery decisions must use explicit target/package provenance and the full package identity, not an inferred `PublishedAs` value.

## Q-19: UTF-8 Basic Authentication with Non-ASCII Credentials

The existing Fkh credential was verified without disclosure to contain ASCII-only username and password values. It cannot test server acceptance of a non-ASCII identity.

Two unauthenticated read endpoints were unsuitable as substitutes: `/dev/metadata` returned HTTP `200` for both a valid ASCII credential and a deliberately invalid UTF-8 Basic username, while `GET /BC/dev/apps?tenant=default` returned HTTP `404` for both. Those responses do not distinguish credential decoding or authentication success, so they provide no UTF-8 acceptance evidence.

Conclusion: Phase 0 cannot claim that the NST accepts UTF-8 Basic authentication for non-ASCII usernames or passwords. Until a separately approved, disposable Fkh/BC identity with a non-ASCII username or password can be tested against an authenticated operation, the direct-POST helper must reject non-ASCII credentials rather than silently choose an encoding.

## Follow-up Measurements

The following Phase-0 measurements remain open:

| ID | Measurement | Current state |
|---|---|---|
| Q-13a | Run an AL CLI group containing only actual test codeunits and compare its duration with DRV on both targets. | Complete on both targets: after the B-1 engine fix, the Fkh DRV runner passed 23/23 without an override and ASINST passed 23/23. |
| Q-13b | Capture green, red, wrong-port, and non-test group result shapes. | Green, wrong-port, and non-test complete; red intentionally blocked. |
| Q-13c | Measure `altool publishapp --schemaupdatemode Synchronize`, including an exact-package retry, on both targets. | Complete on ASINST and Fkh. |
| Q-1 | Determine AL MCP default target selection with and without child-scoped `BC_SERVER_URL`. | Complete: URL overrides the host only; first active launch configuration supplies all unresolved values. |
| Q-2 | Measure Test package-cache freshness for MCP build versus direct compiler build. | Complete; cache is not refreshed. |
| Q-3 | Determine the current AL CLI selection behavior and a reusable ranking policy. | Current timestamp-based extension selection measured; semantic-version ranking remains a Phase-1 implementation decision. |
| Q-5 | Determine exact AL MCP tool names and the custom-agent `tools:` reference form. | Raw MCP tool names complete; host-integrated frontmatter qualification remains unmeasured and must not be guessed. |
| Q-20 | Explain the connection-context difference between stand-alone and VS Code-managed AL MCP. | Complete: the exact `mcp.json` launcher remains connectionless outside the VS Code MCP host; the host-specific mechanism is not identified. |
| Q-21 | Determine whether `al_run_tests` accepts a complete explicit target bundle. | Complete on ASINST: 10 passed with server, instance, port, authentication, and tenant supplied. |
| Q-8 | Determine whether the agent can start or restart VS Code-managed AL MCP. | Complete: VS Code exposes lifecycle commands, but this agent session has no permitted general VS Code command invoker. |
| Q-10 | Determine the MCP behavior for an explicit credentialless UserPassword request. | Complete: no credential elicitation; `UserNotAuthenticatedException` is returned. |
| Q-16 | Determine whether tenant-scoped `Uninstall-NAVApp` and `Unpublish-NAVApp` remove a DEV app cleanly. | Complete on ASINST with a disposable probe app. |
| Q-14 | Determine whether the Automation API can replace ASINST Management DLL lifecycle/recovery. | Complete for this OnPrem target: no; SaaS-only per-tenant Automation API support and ASINST route `404` retain the Management DLL route. |
| Q-18 | Determine whether direct Development Service POST or Fkh should own Fkh-target deployment. | Complete: two valid equal-probe runs have opposite timing winners, so no general performance winner is established; use Fkh for its target/deployment abstraction and retain direct POST as a protocol/diagnostic primitive. |
| Q-19 | Determine UTF-8 Basic authentication acceptance for non-ASCII credentials. | Blocked by the absence of a controlled non-ASCII identity; reject non-ASCII credentials conservatively. |
| Q-9 | Compare MCP and CLI diagnostics for a real failing test without changing product code. | Complete on Fkh: direct CLI and MCP include error text and AL call stacks; mixed CLI groups continue after a failure. |
| Q-22 | Determine whether `Get-NAVAppInfo -TenantSpecificProperties` exposes `PublishedAs` on BC 28. | Complete: the property is absent; it cannot classify Management-DLL versus DEV Endpoint publication. |