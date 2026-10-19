---
name: skill-aproda-al-mcp
description: "AL MCP access (altool launchmcpserver) for Business Central: target selection via aldc.local.json, starter, tool tiers and call rules. Use when calling al_build / al_compile with projectPath, al_publish, al_run_tests, choosing or changing the AL target (launch.json configuration), refreshing the Test project's package cache, or when the al-mcp tools are missing from the session. Aproda custom skill (E-010, D-53)."
---

# Skill: AL MCP Access (level 1)

> **Aproda custom skill** — E-010 phase 2, decision D-53 (see [`../../decisions.aproda.md`](../../decisions.aproda.md) and [`../../readme.aproda.md`](../../readme.aproda.md)).
> **Status:** library and starter covered by synthetic tests (`S-2.*`); live validation (`L-2.*`) pending. The Aproda VS Code extension registration (phase 3) is not shipped yet — use the [interim registration](#9-interim-registration).

## 1. Purpose and boundary

Gives agents the AL MCP server (`al-mcp`, Microsoft's `altool launchmcpserver`) as **level 1**: build, compile, one publish, one test codeunit, with an explicit `projectPath`. It does not own phase gates, test ranges, suites or the target lifecycle. Those belong to [`skill-aproda-deploy-run-verify`](../skill-aproda-deploy-run-verify/SKILL.md) (level 2, the DRV engine).

| Request | Route |
|---|---|
| Compile, build, diagnostics, symbols, one `al_publish`, one codeunit (optionally single methods) | level 1: `al-mcp` |
| More than one codeunit, a range, a suite, a DRV phase gate | level 2: DRV engine |
| `al-mcp` absent or declined for this session | level 2 for the rest of the session |

Never loop N `al_run_tests` calls to emulate a gate, and never spawn your own `launchmcpserver` from a script (Q-20: only the VS Code-hosted server resolves its target).

Files: [`scripts/AprodaAlTarget.ps1`](scripts/AprodaAlTarget.ps1) (shared library, also used by the DRV engine), [`scripts/Start-AprodaAlMcp.ps1`](scripts/Start-AprodaAlMcp.ps1) (starter). Load scripts content-based (SRP-safe, pwsh 7):

```powershell
. ([ScriptBlock]::Create((Get-Content -LiteralPath '<toolkitRoot>\skills\skill-aproda-al-mcp\scripts\AprodaAlTarget.ps1' -Raw)))
```

## 2. Target selection

The selected target is one git-ignored file next to `aldc.yaml`: `<repo>/.github/aldc.local.json` (or `<repo>/aldc.local.json` when `aldc.yaml` sits at the root).

```json
{
  "version": 1,
  "target": { "launchProject": "Base", "launchConfig": "<configuration name in launch.json>" }
}
```

It holds no endpoint data and no secrets; endpoint data is read live from `<launchProject>/.vscode/launch.json`.

| State | Meaning | Action |
|---|---|---|
| `noToolkit` | no `aldc.yaml` under the repository root | stop, ask |
| `absent` | file missing | ask the user which configuration, then write it |
| `invalid` | not strict JSON, wrong `version`, bad path or empty field (`reason` names the rule) | ask, do not infer |
| `stale` | `launch.json` missing/unparseable, configuration name not found (ordinal, case-sensitive) or without `server` | ask, do not infer |
| `configured` | usable; `resolvedLaunch` and `issues` are filled | check `issues` |

- **Read:** `Get-AprodaAlLocalSelection -RepositoryRoot <repo>`; with the Aproda extension (phase 3) `#aldcConfiguration` returns the same data as its `local` block. `Get-AprodaAlLaunchConfigurations` lists the candidates.
- **Change:** the extension command *Select AL Target* (phase 3), or `Set-AprodaAlLocalSelection` **after asking the user**. It refuses a result that would not be `configured`. Never edit `launch.json` to switch targets.
- **Selection is not an acknowledgement.** The once-per-spec environment acknowledgement of DRV stays mandatory before the first publish.
- **Blocking `issues`** (`SERVER_INVALID`, `INSTANCE_MISSING`, `PORT_INVALID`, `NOT_ONPREM`, `AUTH_MISSING`, `AUTH_UNSUPPORTED`, `AUTH_UNKNOWN`, `USERPASSWORD_OVER_HTTP`, `DEPENDENCY_OPTION_INVALID`) block publish, test run and the MCP target; build-only stays possible. Supported authentication: `Windows`, `UserPassword`; `AAD`/`MicrosoftEntraID` stop with `AUTH_UNSUPPORTED`; a missing value is never defaulted.

## 3. Tool tiers

| Tier | Tools | Gate |
|---|---|---|
| 1 — local / read | `al_compile`, `al_build`, `al_getdiagnostics`, `al_symbolsearch`, `al_symbolrelations`, `al_inspectpage`, `al_getpackagedependencies`, `al_getnextobjectid`, `al_downloadsymbols`, `al_addproject`, `al_searchtranslations` | none |
| 1b — local write | `al_writetranslation` (writes XLIFF in the workspace) | normal edit review; ownership with E-005 |
| 2 — shared-target write | `al_publish` (`Synchronize`, or `ForceSync` per D-39, selected target), `al_run_tests` | environment acknowledgement once per spec + VS Code tool confirmation; `ForceSync`: brief information to the user (D-39) |
| 3 — destructive / foreign | `al_publish` with `Recreate` or `forceUpgrade`, or any target other than the selected one | explicit HITL per call; never in a conductor loop |

`al_publish` and `al_run_tests` are never auto-approved in VS Code: the confirmation dialog shows the parameters and is the enforcement point.

## 4. Call rules (C-2)

Every `al_publish` and `al_run_tests` call carries the **complete** target bundle from `local.resolvedLaunch` (via `Get-AprodaAlTargetBundle`), never a partial set and never values that differ from the selection (that is tier 3). The call is then independent of `launch.json` order (altool takes the first `server` configuration for anything unset) and of the MCP host context.

| Bundle field | MCP parameter | From `resolvedLaunch` |
|---|---|---|
| `ServerUrl` | `serverUrl` | `scheme://host` |
| `ServerInstance` | `serverInstance` | `serverInstance` |
| `Port` | `port` | `port` (default 7049 when absent in `launch.json`) |
| `Authentication` | `authentication` | `authentication` (`Windows` or `UserPassword`) |
| `Tenant` | `tenant` | `tenant` (default `default`) |

- `schemaUpdateMode`: `Synchronize` by default. `ForceSync` per D-39 only when a destructive schema change requires it (it drops removed fields **including their data**); tell the user briefly, no separate confirmation. `Recreate` and `forceUpgrade` only after explicit confirmation for that call.
- `UserPassword` only over HTTPS and only toward the host its credential is keyed to; any other combination stops before the call.
- `al_publish` with `appPath` + `skipBuild` publishes exactly the artifact that was built.
- `al_run_tests` takes exactly one `codeunitId`.

## 5. Package cache (Q-2)

Neither MCP `al_build {projectPath: Test}` nor `alc.exe` refreshes the Base package in `Test/.alpackages`; both build green against a stale Base. After a Base build and **before** the Test build:

```powershell
Update-AprodaAlPackageCache -SourceAppFile '<Base>\<Publisher>_<Name>_<Version>.app' -TargetProjectDir '<repo>\Test'
```

It removes older files of that app (`<Publisher>_<Name>_<version>.app`) from `<Test>/.alpackages`, copies the fresh file in, and leaves other apps untouched. A green Test build without this step proves nothing about what a publish will see.

## 6. Session flow (level 1 ↔ 2)

1. `al-mcp` tools present → level 1 (single steps only; see §1).
2. Absent (start mode `manual`, interim registration, or a failed start) → ask the user **once per session** whether to start `al-mcp`; remember the answer in session memory. Yes → the scoped extension tool `startAlMcp` (from phase 3), or the user runs *MCP: Start Server* (interim mode). No → level 2 for the rest of the session, no further prompts.
3. `UserPassword` and no stored credential → credential flow (§7), then start or restart. Wrong password → clear it, re-prompt, restart **once**; a second failure is a blocker.
4. Before the first publish: DRV preflight (dependency check) and the environment acknowledgement. A target or credential change needs a server restart (automatic with the extension, *MCP: Restart Server* in interim mode).

## 7. Credentials

Only the Fkh DPAPI store (`%LOCALAPPDATA%\AprodaFkh\credentials`, keyed by host, D-43). The starter reads it and hands it to the `altool` child process only. A missing credential: extension command *Store Credential for AL Target* (phase 3) or the terminal flow of [`skill-aproda-fkh`](../skill-aproda-fkh/SKILL.md) (`Save-FkhCredential` with `Get-Credential`). **Never ask for a password in chat**, never put one in a file, command line, or terminal environment.

## 8. Failure modes

The starter never removes the whole tool set: on a target problem it starts **build-only** (build, compile, diagnostics and symbol tools work; every target call fails at call time with the server's own error) and logs to stderr (MCP output log) as `[al-mcp-starter] <LEVEL> <CODE> <text>`.

| stderr code | Cause | Fix |
|---|---|---|
| `SELECTION_ABSENT` / `_INVALID` / `_STALE` / `_NOTOOLKIT` | selection state (§2) | select a target |
| `TARGET_BLOCKED <codes>` | blocking issues (§2) | fix `launch.json` |
| `CREDENTIAL_MISSING <host>` | `UserPassword`, nothing stored | §7 |
| `FIRST_CONFIG_DIFFERS <project>` | first `server` configuration of a `launch.json` differs from the selection (informational) | rely on the complete bundle (C-2) |
| `ALTOOL_*` (exit 3), `NO_AL_PROJECT` (4), `PWSH_TOO_OLD` (5), `LIBRARY_LOAD_FAILED` (6) | start aborted | see error text |

- `UserNotAuthenticatedException` at call time: the server never prompts (Q-10); credential missing or wrong, see §6 step 3.
- `No server connection is configured`: a `launchmcpserver` started outside the VS Code MCP host (Q-20); use only the VS Code-hosted server.
- Two `al-mcp` servers: the interim `mcp.json` entry plus the extension provider; remove the interim entry once the extension provides the server.
- `altool` is the one of the active AL Language extension; ranking by parsed version, `.obsolete` folders excluded; the dotnet tool `al` is a fallback with warning `ALTOOL_FALLBACK_DOTNET_TOOL`.

## 9. Interim registration

*Interim until the Aproda extension provides the server (phase 3).* A workspace-level entry that stays local: it is not covered by the managed ignore block — **do not commit it**. The workspace folder named `.github` is the toolkit root in a project (the repository root is anchored one level up):

```jsonc
// <repo>/.github/.vscode/mcp.json — local only, do not commit
{
  "servers": {
    "al-mcp": {
      "type": "stdio",
      "command": "pwsh",
      "args": [
        "-NoProfile", "-NonInteractive", "-Command",
        "& ([ScriptBlock]::Create((Get-Content -LiteralPath '${workspaceFolder}\\skills\\skill-aproda-al-mcp\\scripts\\Start-AprodaAlMcp.ps1' -Raw))) -RepositoryRoot '${workspaceFolder}\\..' -SkillRoot '${workspaceFolder}\\skills\\skill-aproda-al-mcp'"
      ]
    }
  }
}
```

Credential changes or target switches need *MCP: Restart Server* in this mode.
