# Direct Dev Endpoint Publish Protocol (E-010 reference)

> **Source:** *Gustav Gerig AG Base* → `.github/documentation/ALDC/AlMcpDynamicConfiguration.design.md`,
> §7 (validated by Florian, 2026-10-15). Taken over as a standalone reference; content unchanged except
> for the section numbering and the E-010 positioning below.

## Position in E-010

| Aspect | Rule |
|---|---|
| Role | **Level-2b deploy fallback** when `altool publishapp` is unavailable or fails on invocation (answers Q-15). Single deploy fallback for ASINST and Fkh; replaces `fkh publishapp --devScope` as a deploy route (Q-18). Not a route for the agent; called only by the DRV engine. |
| Scope | Publishes DEV extensions — the same scope as `al_publish`, `altool publishapp` and `fkh --devScope`, so no scope mix (Q-6). |
| Authentication | Validated for `Windows` (ASINST NST, HTTP) and `UserPassword` (Fkh, HTTPS port `7049`, HTTP Basic header built in memory from the Fkh DPAPI store, see §4) — Q-17. `AAD`/`MicrosoftEntraID`: not supported. |
| Fallback trigger | `415`, `422`, sync or schema errors are **real failures**, never a reason to try another route or to repeat the POST (see §5). |
| Implementation (phase 4b, X-47) | The §2–§5 rules are implemented by `Publish-DeployRunVerifyDevEndpoint` in the DRV engine (multipart shape, `ExpectContinue = false`, infinite timeout, `Windows` default credentials, `UserPassword` in-memory Basic header via `New-DeployRunVerifyBasicAuthorization`, HTTPS-only, ASCII-only credentials per Q-19, never retried), classified by `Get-DeployRunVerifyPublishOutcome` (`200` Published, `401` AuthFailure, `415` ProtocolError, `422` Duplicate, no response InvocationFailure, other Rejected). `forceUpgrade` is not supported on this route (`FORCEUPGRADE_REQUIRES_ALTOOL`). |
| `DependencyPublishingOption` | The value of the selected `launch.json` configuration (`Default`, `Ignore`, `Strict`), default `Default`; it is always sent on this route. Phase 0 used `ignore` on ASINST and `Default` on Fkh; whether `Default` suffices on ASINST stays open (OS-2, `L-4b.3`). |

## 1. Purpose and boundary

The Business Central Development Service exposes a development publish endpoint. It is the transport used by the AL Language tooling and by BcContainerHelper's `Publish-BcContainerApp -useDevEndpoint` flow. It is useful when a deterministic, scriptable publish primitive is needed without invoking the AL MCP `al_publish` tool.

It is not a general Business Central REST API and must not be confused with OData/API endpoints. The endpoint publishes and synchronizes an AL package, which is a shared-target write operation. The existing target-selection, human approval, dependency order, and post-publish inspection rules still apply.

The official AL MCP `al_publish` tool remains the preferred public abstraction. Direct Dev Endpoint calls are an implementation primitive for controlled automation, diagnostics, or a future ALDC helper where the standard tool does not expose required behaviour.

## 2. Validated endpoint shape

For an OnPrem development service, compose the endpoint from the selected `launch.json` configuration:

```text
{server}:{port}/{serverInstance}/dev/apps
```

The validated request for the stable Toga NST was:

```text
POST http://apd-svw-nst05.aproda.ch:9540/TOGA_FOOD_SA_28_AG_28_CH_FKO/dev/apps?SchemaUpdateMode=synchronize&DependencyPublishingOption=ignore&tenant=default
```

The BcContainerHelper source builds the same endpoint with these optional query parameters:

| Query parameter | Meaning |
|---|---|
| `SchemaUpdateMode` | `synchronize` by default; `forcesync` for a deliberately destructive schema sync; `recreate` for clean/recreate mode. |
| `DependencyPublishingOption` | Optional dependency behaviour. BcContainerHelper includes it only when explicitly supplied. |
| `tenant` | Target tenant, normally `default` in this repository. |

The Development Service does not implement a useful `OPTIONS` probe on this route. A local `OPTIONS` request returned `404`; this did not indicate that `POST` was unavailable. Use an explicit target preflight and the actual publish result instead of treating `OPTIONS` as a capability check.

## 3. Required HTTP request representation

The endpoint does **not** accept a naked `.app` binary as `application/octet-stream`. A direct raw-binary POST reached the NST but was rejected with HTTP `415 Unsupported Media Type`.

The request must match BcContainerHelper's representation:

- HTTP `POST`.
- `System.Net.Http.MultipartFormDataContent`, which sets `Content-Type: multipart/form-data; boundary=...`.
- One `StreamContent` part backed by the `.app` file.
- The part's `Content-Disposition` is `form-data`; its `Name`, `FileName`, and `FileNameStar` are all the package file name.
- Disable `Expect: 100-continue`.
- Use an infinite client timeout for the publish operation.

Minimal PowerShell shape, derived from BcContainerHelper's published implementation:

```powershell
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.UseDefaultCredentials = $true
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
$client.DefaultRequestHeaders.ExpectContinue = $false

$multipart = [System.Net.Http.MultipartFormDataContent]::new()
$fileName = [System.IO.Path]::GetFileName($appFile)
$fileStream = [System.IO.FileStream]::new($appFile, [System.IO.FileMode]::Open)
$part = [System.Net.Http.StreamContent]::new($fileStream)
$disposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
$disposition.Name = $fileName
$disposition.FileName = $fileName
$disposition.FileNameStar = $fileName
$part.Headers.ContentDisposition = $disposition
$multipart.Add($part)

$response = $client.PostAsync($url, $multipart).GetAwaiter().GetResult()
```

Always dispose the multipart content, file stream, HTTP client, and handler after the request. A production helper must convert non-success response bodies to a non-secret actionable error and must not print credentials.

## 4. Authentication

For a `launch.json` configuration with `authentication: "Windows"`, use:

```powershell
$handler.UseDefaultCredentials = $true
```

This lets the HTTP Negotiate/NTLM handshake use the current Windows identity. It does not emit a reusable authorization header and must not be replaced by a manually composed credential string.

For `UserPassword`, use the existing DPAPI-backed Fkh credential store and apply the relevant credential strategy only to the child request/process. For cloud/AAD targets, use the authenticated AL CLI/MCP path unless a separately verified direct protocol exists.

**`UserPassword` — validated mechanism (Fkh, 2026-10-15).**

1. Credential key = host of the selected configuration's `server` (same key as the MCP starter and D-43):

   ```powershell
   $credentialKey = ([uri]$server).Host
   ```

2. Load the store SRP-safe from its content and read the credential:

   ```powershell
   . ([ScriptBlock]::Create((Get-Content -LiteralPath $credentialStorePath -Raw -Encoding utf8)))
   $credential = Get-FkhStoredCredential -Key $credentialKey
   ```

3. Build an HTTP Basic header in memory, only on this request's `HttpClient`:

   ```powershell
   $basicToken = [Convert]::ToBase64String(
     [Text.Encoding]::ASCII.GetBytes(
       $credential.UserName + ':' + $credential.GetNetworkCredential().Password
     )
   )
   $client.DefaultRequestHeaders.Authorization =
     [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', $basicToken)
   ```

The password was not printed, not written to a file and not set as a user/machine environment variable; the
header existed only in the single request's `HttpClient`.

Rules for the production helper:

- **HTTPS only.** Basic auth sends the password reversibly encoded; refuse a `UserPassword` publish to an
  `http://` server instead of sending the header.
- **No Windows credentials alongside.** Keep `UseDefaultCredentials = $false` on the handler for `UserPassword`.
- **Encoding.** `ASCII` silently replaces non-ASCII characters (e.g. umlauts) in user name or password with
  `?`, which fails authentication with a misleading message. **Decided (Q-19, 2026-10-15):** reject non-ASCII
  credentials with a clear message; UTF-8 acceptance by the NST is unproven (the only available credential is
  ASCII-only, and unauthenticated read endpoints cannot tell valid from invalid credentials).
- **Missing credential** → the Fkh save flow (D-43), never a prompt inside the request code.
- **Never log** request headers; dispose the client and handler, and drop `$basicToken` right after the call.

## 5. Package identity and repeat publishing

The Development Endpoint allows repeat deployment of the same **app version** for a DEV application when the rebuilt `.app` has a new package identifier. This was validated against `Gustav Gerig AG Base` version `25.0.0.158`:

1. A direct multipart POST of the already deployed package returned HTTP `422 Unprocessable Entity` with `InvalidOperation`: duplicate package ID.
2. The package was rebuilt without changing the app version.
3. A direct multipart POST of the rebuilt package returned HTTP `200 OK`.
4. The target reported the app as `IsPublished: True`, `IsInstalled: True`, `SyncState: Synced`, and `ExtensionDataVersion: 25.0.0.158`.

Consequently, version equality alone does not identify a duplicate DEV publish. The relevant distinction is the package ID embedded in the `.app`:

| Package state | Expected result |
|---|---|
| Exact same package ID already published | HTTP `422` duplicate package ID; no new deployment. |
| Rebuilt package with a new package ID, same app version | May publish successfully as a DEV deployment. |
| New package requires schema removal | `Synchronize` can fail; `ForceSync` requires an explicit destructive-data acknowledgement. |

Direct requests must not use repeated POST retries as a recovery mechanism. After a failed publish, inspect the target app state. A package can be published but `NotSynced`; attempting the exact same package again then fails with a duplicate-package error. Remove only the identified uninstalled/unsynced failed package, confirm its removal, and republish deliberately. Never remove an installed or otherwise healthy package merely to retry.

## 6. Source evidence and validation

The request shape was inspected in the public BcContainerHelper repository, [`AppHandling/Publish-NavContainerApp.ps1`](https://github.com/microsoft/navcontainerhelper/blob/main/AppHandling/Publish-NavContainerApp.ps1): the `useDevEndpoint` branch constructs `/dev/apps`, configures Windows default credentials, creates `MultipartFormDataContent`, attaches `StreamContent` with form-data disposition, and calls `PostAsync`.

Validated on 2026-10-15 against `TOGA_FOOD_SA_28_AG_28_CH_FKO`:

- `OPTIONS` -> HTTP `404`.
- Raw `application/octet-stream` POST -> HTTP `415`.
- Multipart post of an existing package -> HTTP `422` duplicate package ID.
- Multipart post of a newly rebuilt package with the same app version -> HTTP `200`; app installed and synced.

Validated on 2026-10-15 against the Fkh target `flobi-wan-kenobi-gustavgerig-dev-deployment` (HTTPS, port
`7049`, `UserPassword` from the Fkh DPAPI store):

- Multipart post of the current Base app -> HTTP `200`.
- Follow-up check via AL MCP: codeunit `59021` on `CRONUS CH` -> 10 passed, 0 failed, 0 skipped.
