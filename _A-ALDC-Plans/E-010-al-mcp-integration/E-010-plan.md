# E-010 — AL MCP integration (`altool launchmcpserver`) as a reusable Aproda capability

> **Status: Approved 2026-10-15 (Florian) — decision record D-53 (+ addenda D-8, D-15, D-26, D-39, D-43).**
> Pre-step B-1/B-2 implemented and live-validated; B-3 refuted. Next: phase 2. Implementation details live in
> [`E-010.spec.md`](E-010.spec.md), tests in [`E-010.test-plan.md`](E-010.test-plan.md), release and migration in
> [`E-010.rollout.md`](E-010.rollout.md). This file remains the architecture and review document.

## Folder contents

| File | What it is |
|---|---|
| [`AlMcpDynamicConfiguration.design.md`](AlMcpDynamicConfiguration.design.md) | Original design proposal, snapshot of the first import (2026-10-15), **unchanged**; later revisions in the source project are not taken over yet. Its relative links point into the source project and do not resolve here. |
| [`prototype/Start-AlMcpWithFkhCredential.ps1`](prototype/Start-AlMcpWithFkhCredential.ps1) | Validated starter (hardcoded credential key, Base + Test). |
| [`prototype/mcp.json`](prototype/mcp.json) | Validated `Base/.vscode/mcp.json` registration. |
| [`dev-endpoint-publish-protocol.md`](dev-endpoint-publish-protocol.md) | Validated direct Dev Endpoint publish (multipart POST to `/dev/apps`) — source design §7, with its E-010 positioning. |
| [`AlMcpE010Phase0Evidence.md`](AlMcpE010Phase0Evidence.md) | Phase-0 measurement report from *Gustav Gerig AG Base* (2026-10-15), copied unchanged; summarized under *Phase-0 evidence*. |
| `E-010-plan.md` | This review + recommended solution (architecture document of the epic). |
| [`E-010.spec.md`](E-010.spec.md) | Implementation specification per phase: files, functions, data shapes, messages, exit codes. |
| [`E-010.test-plan.md`](E-010.test-plan.md) | Synthetic (`S-*`) and live (`L-*`) tests, safety rules, acceptance mapping. |
| [`E-010.rollout.md`](E-010.rollout.md) | Release content, prerequisites, distribution changes, breaking changes, migration, rollback. |

## Verdict

**Good idea — adopt, with corrections.** The prototype closes a real, documented gap in ALDC and reuses
the right building blocks (Fkh credential store, `launch.json` as endpoint source, DRV as lifecycle owner).
The design is close to D-8/D-26/D-43 already. It underestimates three things, all found in the official
documentation (fetched 2026-10-15) rather than in the prototype:

1. **The target is chosen per tool call, not per server.** MCP `al_publish` takes `serverUrl`,
   `serverInstance`, `port`, `authentication` and `schemaUpdateMode` (`Synchronize` | `ForceSync` |
   `Recreate`) as call parameters ([al_publish](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/al-agent-tools/al-tool-publish)).
   The local profile therefore selects only *which credential is injected* — it does not bind the server
   to that target. An agent can send the injected UserPassword credential to any `serverUrl`, or publish
   with `Recreate` against a shared container.
2. **ALTool has grown CLI verbs the design does not know about.** ALTool 18.1 ships `runtests` (structured
   JSON, exit code, `--testgroups` = several codeunits over one session) and `publishapp`, both honouring
   `BC_SERVER_URL/INSTANCE/PORT/USERNAME/PASSWORD`
   ([ALTool](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-al-tool)).
   They become the DRV engine's preferred tools (see *Routing*).
3. **Startup failure = silent tool absence.** A non-interactive MCP starter that throws (missing
   credential, wrong profile) removes *all* `al-mcp` tools from the session with only an MCP output-log
   entry — the same failure class E-006 fought (`al_symbolrelations`, `al_get_diagnostics`).

## What the integration actually buys ALDC

| Gap today | Source | AL MCP answer |
|---|---|---|
| Building one specific project in multi-root works only via the terminal route (DRV `buildonly`, `alc.exe /project:`) — deterministic, but not native: own path/cache handling, unstructured output. Native `al_build {"scope":"current"}` binds to the focused editor. | DRV skill → *Build route* | MCP `al_build` / `al_compile` take an explicit `projectPath` and return structured results |
| No compile-only validation without producing an `.app` | — | `al_compile` (MCP only) |
| Agents cannot publish / run a single test — "human step" | `al-developer.agent.md`, `copilot-reference.md` | `al_publish` (`appPath` + `skipBuild` = publish exactly the DRV-built artifact), `al_run_tests` |
| Next free object ID | E-004 | `al_getnextobjectid` — overlaps E-004; E-004 should be re-scoped against it |
| XLIFF translation | E-005 | `al_searchtranslations`, `al_writetranslation` (present in `tools/list`, undocumented) — E-005 should evaluate them before building own tooling |

## Required corrections to the design

| # | Correction | Why |
|---|---|---|
| C-1 | Starter: export the complete bundle `BC_SERVER_URL` + `BC_SERVER_INSTANCE` + `BC_SERVER_PORT` (+ `BC_SERVER_USERNAME`/`PASSWORD` for `UserPassword`) from the selected config, never `BC_SERVER_URL` alone — defence in depth behind C-2. There is no environment variable for the authentication method; without credentials it merges from the **first** `server` configuration of the project's `launch.json`. If that first configuration differs from the selection, the starter warns (a `Windows` selection behind a `UserPassword` first config fails safely, without any credential in the process). Engine: always pass `--server`, `--serverinstance`, `--port`, `--authentication` explicitly to the CLI. | **Measured (Q-1):** `BC_SERVER_URL` overrides only the host; the rest merges from the first launch configuration. URL alone paired an ASINST host with Fkh `UserPassword` — `UserNotAuthenticatedException`, and the Fkh credential was sent to the wrong host. Precedence of `BC_SERVER_INSTANCE`/`PORT` is assumed equal — verify in Phase 2. |
| C-2 | Agent rule: **every** `al-mcp/al_publish` and `al_run_tests` call carries the complete target bundle from `#aldcConfiguration → local.resolvedLaunch` (`serverUrl`, `serverInstance`, `port`, `authentication`, `tenant`) — never a partial set, never values that differ from the selection (that is Tier 3). `schemaUpdateMode`: `Synchronize` by default, `ForceSync` per D-39 (when a destructive schema change requires it; inform the user briefly, no separate confirmation); `Recreate` and `forceUpgrade` require explicit HITL. `al_publish` / `al_run_tests` are never auto-approved in VS Code. | **Measured:** both tools honour the complete bundle (Q-21: `al_run_tests` 10/10 on ASINST with explicit target); it makes the call independent of `launch.json` order (Q-1) and of the MCP host context (Q-20). The VS Code tool-confirmation dialog shows the parameters and is the enforcement point. Tiering mirrors D-48. |
| C-3 | Missing credential → set it through the existing Fkh store flow **before** the server starts (extension `resolveMcpServerDefinition`, see below). Interim `mcp.json` mode: start build-only, warn on `stderr`; the agent runs the Fkh save flow in a terminal and asks for a server restart. | Same behaviour as DRV today (D-43); avoids silent removal of build/compile/symbols tools (finding 3). **Measured (Q-10):** the server itself never prompts — a missing credential only surfaces as `UserNotAuthenticatedException` at call time. |
| C-4 | Starter writes **nothing to stdout** before `altool` takes over. | stdout is the JSON-RPC channel; one stray `Write-Output` breaks the server. |
| C-5 | Run the starter and the new target resolver under **pwsh 7**. | **Measured:** pwsh 7.6.6 `ConvertFrom-Json` parses the real `launch.json` with line comments *and* a trailing comma — no regex stripping (`(?<!:)//.*?$`) needed. Windows PowerShell 5.1 is not covered by this evidence. The local selection file is strict JSON and needs none of this. |
| C-6 | Credential-store path resolved relative to the skill folder (passed in, since `$PSScriptRoot` is empty under SRP-safe loading), not `<Base>\..\.github\skills\…`. | Prototype path breaks in the fork (`skills/` at root) and in repos without a `Base` folder. |
| C-7 | Use the `altool` of the **active** AL Language extension (`vscode.extensions.getExtension('ms-dynamics-smb.al').extensionPath` when registered by the Aproda extension). Interim starter: parsed semver ordering across valid `ms-dynamics-smb.al-*` folders, both layouts (`bin\altool.exe`, `bin\win32\altool.exe`), stop on an invalid version or an unresolvable tie — never `LastWriteTime`. The global `al` dotnet tool (D-34) is a fallback only, with a version-mismatch warning. | **Measured (Q-3):** the workstation has dotnet-tool `al.exe` **18.0.41** in `PATH` next to the extension's `altool.exe` **18.1.43**; the prototype picks by folder timestamp and ignores `al.exe`. Same compiler as the editor → same diagnostics. Multi-folder ranking is validated with a synthetic test in Phase 2 (only one extension folder installed). Folders listed in VS Code's `extensions/.obsolete` (pending deletion) are excluded (spec §2.4). |
| C-8 | Anchor the server on the repository root; the project list is every direct sub-folder of the repository root that contains an `app.json` (ordinal order). | Removes the `${workspaceFolder:Base}`/`Test` naming dependency (design §10, "Workspace names"). |

## Recommended solution

Same shape as DRV (D-8): **immutable engine in the skill, tiny project-local config, registration separate.**

```text
skills/skill-aproda-al-mcp/
  SKILL.md                          scope, tool tiers, HITL rules, MCP-vs-DRV boundary
  scripts/Start-AprodaAlMcp.ps1     host-agnostic starter (C-1…C-8)
  scripts/AprodaAlTarget.ps1        shared library: selection, launch resolution, target bundle, altool locator (also used by DRV)
<project>/.github/aldc.local.json             git-ignored developer selection next to aldc.yaml (no endpoint data, no secrets)
<project>/.github/.vscode/mcp.json            interim registration only (local, do not commit; spec §3.5), replaced by the extension
```

**Registration — target: the Aproda VS Code extension.** VS Code lets an extension register MCP servers
(`contributes.mcpServerDefinitionProviders` + `vscode.lm.registerMcpServerDefinitionProvider`; confirmed in
the VS Code MCP developer guide, 2026-10-14). The provider maps cleanly onto the open points:

| Provider hook | Use in E-010 |
|---|---|
| `provideMcpServerDefinitions` | Resolve git root and AL projects the way `#aldcConfiguration` does (D-24); take the active AL extension path (C-7); return a `McpStdioServerDefinition` that runs the PS starter. No tracked `mcp.json`, no workspace-folder names (C-8). |
| `resolveMcpServerDefinition` | Called right before start and may interact with the user: check the Fkh store, run the Fkh save flow on a miss (C-3). |
| `onDidChangeMcpServerDefinitions` | Target switch (QuickPick, or a change of `aldc.local.json` / the selected `launch.json` config seen by a file watcher) → `resolve` reads the credential of the **new** target, or runs the Fkh save flow if none is stored → VS Code restarts the server. |
| Extension UI | Visible notification on start failure instead of a silent MCP-log entry (finding 3). |
| `vscode.debug.onDidStartDebugSession` (optional) | The only public signal of the developer's choice in *Run and Debug* (Q-11): if a started AL session uses a different `launch.json` configuration than `aldc.local.json`, offer "Switch ALDC target to *X*?" — never switch silently (selection ≠ acknowledgement). |
| Scoped LM tool, e.g. `aprodaAldc_startAlMcp` | Lets the agent start/restart **only** `al-mcp` via `workbench.mcp.startServer` / `restartServer` (Q-8), instead of granting a general VS Code command runner (least privilege). |
| User setting `aprodaAldc.alMcp.start` | `auto` (default): the extension starts `al-mcp` itself as soon as an AL project or AL workspace is open; `manual`: only on request (command or tool). Never in a non-AL window. Spec §4.3a. |

**Why the credential is bound per server process, not per call.** `altool` takes UserPassword credentials
only from `BC_SERVER_USERNAME`/`BC_SERVER_PASSWORD` in its own environment, which is fixed when the process
starts; MCP `al_publish` has no credential parameter. "Password follows the target" is therefore achieved
by restart-on-target-change (a few seconds, automatic). It is also the safer binding: one process = one
host = one credential, so a password can never be sent to a different host. Microsoft uses the same model
for the AL extension's own profiling/snapshot MCP proxies (connection and authentication fixed for the
proxy's lifetime, derived from `launch.json`). Rejected: a wrapping proxy MCP that injects credentials per
call — duplicates Microsoft's server and must track its tool schema.

The extension never holds the secret: it only triggers the Fkh flow; the PS starter reads the DPAPI store
and injects it into the server process. Not AL-Language-independent: the server *is* `altool` from the AL
Language extension (which every AL developer has anyway); the global `al` dotnet tool is only a fallback.
`.vscode/mcp.json` stays the interim registration until the extension ships.

## Target selection — one git-ignored file, read by everyone

Today the selected target lives in the **tracked** `deploy-run-verify.config.jsonc` (`launchConfig`, plus the
`server`/`serverInstance`/`tenant` overrides), i.e. it is shared through Git although each developer targets
their own container. E-010 replaces this with one local file:

```json
// <project>/.github/aldc.local.json — git-ignored, per developer, per repo
{
  "version": 1,
  "target": {
    "launchProject": "Base",
    "launchConfig": "flobi-wan-kenobi-gustavgerig-dev-deployment"
  }
}
```

**Name: `.github/aldc.local.json`.**

- Sits next to `.github/aldc.yaml` (toolkit root) and pairs with it: `aldc.yaml` = layer configuration
  (tracked in the fork, delivered by the sync and git-ignored in projects); `aldc.local.json` = personal,
  ignored everywhere.
- `.local.` is the established marker for personal, git-ignored overrides (`CLAUDE.local.md`,
  `.claude/settings.local.json` are already in the fork's `.gitignore`).
- Strict JSON, not JSONC/YAML: the file is machine-written (DRV question, extension QuickPick), needs no
  comments, and parses without help in Windows PowerShell 5.1, pwsh and Node. YAML would need a parser the
  PowerShell estate does not have.
- Generic name, not `launch-target.*`: further per-repo, per-developer values can join under their own key
  without a second file.

| Consumer | How it reads the file |
|---|---|
| Aproda extension (MCP registration) | Directly; file watcher → restart with the new target's credential |
| DRV engine | Directly, from the git root; `launch.json` is read from `target.launchProject`, no longer from the DRV config's own folder |
| Agents | Via `#aldcConfiguration` (see below) |

Rules:

- **Single source, no fallback.** `launchConfig` and the `server`/`serverInstance`/`tenant` overrides are
  **removed** from the DRV config template and from the engine with this change. The tracked DRV config keeps
  only project facts (app order, runner, company, test range).
- **Missing file.** DRV asks the existing environment question (selection from `launch.json`) and writes the
  answer to the file. The extension does the same through its QuickPick.
- **Migration.** A DRV config that still contains `launchConfig` or a server override → the engine stops with
  a named migration error, never ignores it silently. The agent offers to move the value into
  `aldc.local.json` (HITL) and to delete the lines from the tracked config (part of the next commit).
- **Selection ≠ acknowledgement.** The file preselects; DRV still asks for the once-per-spec environment
  acknowledgement before the first publish.
- **Stale selection.** `launchConfig` no longer present in `launch.json` → treated like a missing file (ask
  again), never a guess.
- **Scope.** Only *per-repo, per-developer* values belong here. Workstation properties (BCQuality path,
  `fkh.backendUrl`) stay in user settings — that is why E-006 rejected `aldc.local.yaml` for the BCQuality
  path (D-49), and it remains correct for those.
- **Distribution.** Never on the `aproda-sync.json` allowlist; the `.gitignore` entry is added by project
  bootstrap/initialization.

**`#aldcConfiguration` returns both files**, side by side and never merged — same pattern as the existing
`bcquality.home` (declared) vs `resolvedHome` (live) split:

```jsonc
{
  "state": "configured",
  "configurationPath": "…/.github/aldc.yaml",
  "toolkitRoot": "…", "plansRoot": "…", "layerVersion": "…", "bcquality": { … },   // unchanged
  "local": {
    "state": "configured",            // | "absent" | "invalid" | "stale" (launchConfig not in launch.json)
    "path": "…/.github/aldc.local.json",
    "target": { "launchProject": "Base", "launchConfig": "…" },
    "resolvedLaunch": {               // read live from launch.json — endpoint data, never secrets
      "server": "https://…", "serverInstance": "BC", "tenant": "default",
      "environmentType": "OnPrem", "authentication": "UserPassword"
    }
  }
}
```

Guidance text in the result: *selection only — not an environment acknowledgement; `absent`/`stale` means
ask the user, never infer a target*. No credential state is reported (not even "stored: yes/no").

## Authentication — branch on the selected config's `authentication`

Two independent axes: the **adapter** (transport) follows from the host (D-26: `*.cloudapp.azure.com` → Fkh,
else ASINST); the **authentication** follows from `launch.json → authentication`. Only one value needs a
username and password. Values per MS Learn *Launch JSON file* (`UserPassword`, `Windows`, `AAD`) and the
AL extension IntelliSense, which adds `MicrosoftEntraID` as the newer name of `AAD` and as the **default**.

| `authentication` | Typical target | Secret | AL MCP route | Source of the secret |
|---|---|---|---|---|
| `Windows` | ASINST | none — current Windows identity | inject nothing; target switch needs no credential step | — |
| `UserPassword` | Fkh today | username + password | inject `BC_SERVER_USERNAME`/`BC_SERVER_PASSWORD` at start; restart on target change | Fkh DPAPI store, keyed by host (D-43) |
| `AAD` = `MicrosoftEntraID` | Fkh later (OnPrem Entra needs `primaryTenantDomain` in `launch.json` and the NST on `AccessControlService`) | token, no password | `al_auth_login` (MSAL browser sign-in, token cached on disk) or `BC_ACCESS_TOKEN`; documented for **cloud**, OnPrem Entra unverified (Q-12) | MSAL / VS Code sign-in — never the Fkh store |

Rules:

- Fkh store lookup and the Fkh save flow run **only** for `UserPassword`.
- `AAD` and `MicrosoftEntraID` are treated as one value.
- Missing or unknown value → stop and ask. **Finding:** the DRV engine today defaults a missing value to
  `Windows`, while the AL extension defaults to `MicrosoftEntraID` — the two disagree on the same
  `launch.json`. Remove the silent default with this change.
- Scope of E-010: `Windows` and `UserPassword` implemented and validated. `AAD`/`MicrosoftEntraID` gets the
  branch and a clear "not yet supported" stop, until the first Fkh Entra container exists to measure against.
  (The MS runner glue already accepts `AAD`; the DRV engine has no path for it.)

**Tool tiers (D-48 pattern).**

| Tier | Tools | Gate |
|---|---|---|
| 1 — local / read | `al_compile`, `al_build`, `al_getdiagnostics`, `al_symbolsearch`, `al_symbolrelations`, `al_inspectpage`, `al_getpackagedependencies`, `al_getnextobjectid`, `al_downloadsymbols`, `al_addproject`, `al_searchtranslations` | none |
| 1b — local write | `al_writetranslation` (writes XLIFF in the workspace) | normal edit review; ownership with E-005 |
| 2 — shared-target write | `al_publish` (`Synchronize`, or `ForceSync` per D-39, selected target), `al_run_tests` | DRV-style environment acknowledgement once per spec + VS Code tool confirmation; `ForceSync`: brief information to the user (D-39) |
| 3 — destructive / foreign | `al_publish` / `altool publishapp` with `Recreate` or `forceUpgrade`, or an explicit foreign target | explicit HITL per call; never in a conductor loop |

## Routing — `al-mcp` first, then the DRV engine; `altool` inside the engine

**What `altool.exe` is.** Microsoft's AL toolchain binary (AL Language extension; also a dotnet tool) with
three faces: CLI verbs (`compile`, `workspace compile`, `publishapp`, `runtests`, `auth`, `graph` …) for
scripts; `launchmcpserver` (= `al-mcp`) for agents; `launchlspserver` and the profiling/snapshot proxies.
`al-mcp` and the CLI are two interfaces to the same tool, not alternatives — the D-48 pattern (MCP for the
agent, CLI for scripts). Verified locally 2026-10-15 (`altool --help`, 18.1.43): no CLI verb and no
documented MCP tool lists, uninstalls or unpublishes apps on a server.

**Why the agent does not call the `altool` CLI itself for target operations.** The CLI reads the password
from `BC_SERVER_PASSWORD` of the calling process; in the agent's terminal that puts the secret into a shared
session (design §8 rule 3). MCP keeps it inside the server process, and the VS Code confirmation dialog shows
the parameters. Credential-free verbs (`compile`, `workspace compile`, `GetPackageManifest`) are fine in the
terminal (already DRV *Build route* 4).

**Nested fallback** (decided 2026-10-15):

```text
Level 1  al-mcp        build, single publish, 1 test codeunit
                       ├ always first: engine preflight (dependency check, D-52) + environment acknowledgement
                       └ > 1 codeunit / range / suite / phase gate → engine test run
Level 2  DRV engine    al-mcp not running, or declined for this session
         per step:     a. altool CLI  →  b. legacy route (loaded only when reached)
         Build         altool compile / workspace compile → alc.exe
         Deploy        altool publishapp (Dev Endpoint) → direct Dev Endpoint POST (both adapters, Q-18)
         Test          altool runtests --testgroups → web-client runner + K:-DVD DLLs
         Preflight,    Fkh: fkh · ASINST: Mgmt DLL (read and cleanup only)
         recovery
```

**Package-cache refresh is mandatory on every route, level 1 included (Q-2 measured).** Neither MCP
`al_build {projectPath: Test}` nor `alc.exe /project:Test` refreshes the Base package in `Test/.alpackages`;
both built green against a 15-day-old Base. After a Base build, the fresh Base `.app` is copied into
`Test/.alpackages` before Test is built — by the engine on level 2, by the skill procedure on level 1. A green
Test build without that step proves nothing about what a publish will see.

**Target resolution in `altool` (Q-1 measured).** Without explicit values the resolver takes the **first**
`server` configuration of the project's `launch.json` — configuration order is operational behaviour, not
cosmetics (reversing the order of two identical entries switched ASINST ↔ Fkh). `BC_SERVER_URL` overrides only
the host; instance, port and authentication still merge from that first configuration. Consequences (C-1, C-2):

- **Never a partial target.** Either the complete bundle / all parameters, or none.
- **MCP (level 1):** every target call carries the complete bundle (C-2); the starter's environment bundle is
  only the safety net (C-1). No developer has to reorder a tracked `launch.json`.
- **Host context matters (Q-20):** the exact `mcp.json` launcher run as an independent process stayed
  connectionless (`No server connection is configured`), the same server under VS Code resolved its target.
  The mechanism is not identified (VS Code's MCP *roots* are a plausible candidate). Only the VS Code-hosted
  server is a valid level 1; scripts never spawn their own `launchmcpserver`.
- **Engine (level 2):** every `altool` call gets `--server`, `--serverinstance`, `--port`, `--authentication`
  explicitly, so `launch.json` order does not matter there.
- **`UserPassword` only over HTTPS** and only towards the host the credential is keyed to (D-43); any other
  combination stops before the call.

The deploy fallback is the direct multipart POST to `{server}:{port}/{serverInstance}/dev/apps`, validated
for both adapters (ASINST/`Windows`, Fkh/`UserPassword`) — protocol, error semantics (`415`, `422` duplicate
package ID) and recovery rules in [`dev-endpoint-publish-protocol.md`](dev-endpoint-publish-protocol.md).
Engine-only, never an agent route. It is the single deploy fallback for both adapters and replaces
`fkh publishapp --devScope` as a deploy route (Q-18); `fkh` stays for target verification, app-state
inspection and recovery.

**Session flow (level 1 ↔ 2).**

1. `al-mcp` tools present → level 1.
2. Absent (start mode `manual`, interim registration, or a failed start) → ask the user **once per session** whether to start `al-mcp`; record the answer in session
   memory. Yes → start via the scoped extension tool (`workbench.mcp.startServer`, Q-8), or by the user via
   *MCP: Start Server* in interim mode. No → level 2 for the rest of the session, no further prompts.
3. Credential missing (`UserPassword` only) → Fkh store flow as DRV does today (D-43), then start/restart.
   Wrong password → clear, re-prompt, restart **once**; second failure = blocker.

**Publish scope — everything through the Dev Endpoint (decides Q-6).** `al_publish`, `altool publishapp` and
`fkh --devScope` all publish DEV extensions. `Publish-NAVApp` (Mgmt DLL) only accepts `-Scope Global|Tenant`
(MS Learn, BC 28 module) — it can **not** publish a DEV app and is therefore **never** a publish fallback; it
would mix scopes on the same NST. Today's ASINST engine route publishes with `Publish-NAVApp -Scope Tenant`
(PTE-like, not DEV; `AprodaDeployRunVerify.psm1`, ASINST deploy). A Global app and a DEV app with the same
`id` + `version` block each other (`422 … already deployed on another tenant`, MS Learn). Consequences:

- The Mgmt DLL remains for ASINST **read and cleanup only** — dependency preflight, state, recovery
  (`Get-NAVAppInfo`, `Uninstall-`/`Unpublish-NAVApp`) — and is loaded only when such a step runs.
- Versions published by the old Mgmt-DLL route (Tenant/PTE) or Global, **where present**, are removed once per
  NST with explicit HITL (uninstall/unpublish can affect data). Provenance can **not** be read from the NST:
  `PublishedAs` is absent on BC 28 and DEV packages also report `Scope=Tenant` (Q-22). The cleanup therefore
  lists candidates by **full package identity** (name, publisher, version, installed, sync state) and the human
  decides per package; it never classifies "non-DEV" automatically.

**K:-DVD and runner glue only on the legacy test route.** The four client DLLs and the version detection via
`Get-NAVServerInstance` exist only for the web-client runner. With `altool runtests` neither K: nor the Mgmt
DLL is touched for build and test. Phase 0 exposed a defect on the legacy route: the engine's strict
major/minor gate rejects every BC 28.x target with x > 0, because client DLLs always report `28.0.*` (the Fkh
container's own DLL: `28.0.53322.0`; CH DVD 28.0–28.6: all `28.0.*`) while the server reports
`28.3.52162.53362`. With an in-memory major-only override the Fkh runner ran green (see *Phase-0 evidence*).

**Test-run routing.** MCP `al_run_tests` accepts exactly one `codeunitId` (+ optional method names) — no list,
range or suite (confirmed 2026-10-15 in a real project).

| Request | Route |
|---|---|
| 1 codeunit (optionally single methods) | level 1: `al_run_tests` |
| > 1 codeunit, a range, a suite, a DRV phase gate | engine: one batched `altool runtests --testgroups` → fallback web-client runner (new `runonly` mode; today only `full`/`buildonly`/`skipbuild`) |
| never | agent looping N MCP calls for a gate, or parallel runs — separate sessions, no single report, shared test data can collide |

Range → group file: intersect the range with the test app's `Subtype = Test` codeunits, so non-test IDs are
never sent. The engine normalizes the `runtests` JSON (or XUnit on fallback) into the existing summary; the
phase-gate verdict stays deterministic (D-8).

**`runtests` result handling (Q-13 measured).** Exit code and `data.success` alone do **not** prove a
complete run:

| Observed | Rule |
|---|---|
| A non-test codeunit (setup/helper) in the group stopped the run after the first group (`A task was canceled.`), yet `succeeded: true`, `data.success: true` | Filter to `Subtype = Test` before the call (above). |
| A group of only a non-test codeunit: `total: 0`, `results: []`, `succeeded: true` | Empty run = failure of the step, not green. |
| Every run | **Completeness check:** every requested codeunit must appear in `data.results`; a missing one is an *invocation* failure (fallback allowed), not a test result. |
| Blank-method entries in `results` (framework completion records): 25 entries vs 23 XUnit test cases for the same range | Drop blank-method entries before counting, so both routes report the same totals. |
| Diagnostic noise before a successful JSON (`A task was canceled.`, `Index was out of range … chunkLength`) | Evaluate only the structured JSON, never the noise. |
| Wrong port: exit 1, `succeeded: false`, `errorDetails.retryable: true` | Invocation failure → fallback allowed. |
| Red test (Q-9): exit 1, `succeeded: false`, `errorDetails.code: TestRunFailed`; failing method with error text **and AL call stack** in `output` — identical shape via MCP `al_run_tests` | Test result, **no** fallback. Enough detail for the DRV triage patterns. |
| Red test also produces a blank-method record with status failed and the same output (11 passed, 2 failed for one failing method) | Count and triage failures only from non-empty `methodName`; the blank record is de-duplicated. |
| Mixed group red 59020 + green 59021: the session continued, 59021 10/10; aggregate exit 1, `data.success: false` | A red codeunit does not stop later groups; judge only the aggregate after all groups. |

Measured durations, same tests (59010, 59013 = 23 test cases):

| Target | `altool runtests --testgroups` | DRV web-client runner (`59010..59013`) |
|---|---:|---:|
| ASINST | 10.8 s | 45.9 s |
| Fkh | 3.8 s | 15.7 s wall-clock (3.5 s test execution; with major-only override) |

**Capability detection — no fixed version gate.** Availability depends on the installed `altool` (varies per
developer) *and* on the target server. A hard rule like "BC < 29" would be wrong: `al_run_tests` worked on
BC 28 although the docs say "2026 wave 2", and the MS tool list lags behind (`al_run_tests` is undocumented
but present).

| Stage | How | Answers |
|---|---|---|
| a. Present? | CLI: parse `altool --help` once per run / `altool <verb> --help` exit code. MCP: the server's tool list. | Does this `altool` have it? |
| b. Works on this target? | Outcome of the first real call per target; an **invocation** failure pins the legacy route for that target for the rest of the run. | Does the server support it? |
| c. Learn | The report records `altool` version, BC version and the route per step. | Evidence, not code rules |

**Fallback only on invocation failure — never on a red result.** `succeeded: false` alone does **not**
distinguish the two (Q-9: a red test also yields exit 1 and `succeeded: false`). Classify by
`errorDetails.code`: `TestRunFailed` = tests ran and failed → that is the result, no re-run on another runner;
connection/invocation codes (e.g. `ConnectionFailed`, `UnknownError` with `retryable: true`) or an incomplete
result (completeness check) → fallback allowed. The same for
`publishapp`: a compile, sync or schema error is a real failure, not a fallback trigger — and so is a `422`
duplicate package ID (measured on both targets: exact-package retry → exit 1 with `422 duplicate package ID`).
Since `publishapp` returns exit 1 for both kinds, the engine classifies by the error content, never by the exit
code alone: inspect the target state, never repeat the publish. Otherwise a red test would be retried on other
routes until it turns green.

Every step records which route ran, like the existing *Build route* evidence.

**Inner loop outside DRV.** `al_compile`, a single `al_publish`, a single `al_run_tests` are also usable
directly by `al-developer` under the tier rules above; they never replace a DRV phase gate.

## Fit with ALDC decisions

Recorded 2026-10-15 as **D-53**; the addenda listed below are written in `decisions.aproda.md` (D-8, D-15,
D-26, D-39, D-43).

| Decision | Fit |
|---|---|
| D-4 / D-16 | New `skill-aproda-al-mcp` = net-new primitive with `.aproda` naming; D-16 confirmation before the first file. |
| D-8 | Starter = engine + project-local config — matches. Level 1 moves single steps into the agent; phase gates stay in the engine, which now prefers the `altool` CLI. Needs an addendum. |
| D-9 | Wiring needed in `al-developer`, `al-implement-subagent` (Tier 1), `al-developer` only for Tier 2. Conductor unchanged. |
| D-15 | K:-DVD runner DLLs and runner glue become the legacy test route, loaded only on fallback. Needs an addendum. Its strict major/minor client-DLL gate is a defect for BC 28.x > 0 — fixed in the *Pre-step* (B-1). |
| D-18 / D-19 | Skill ships through the existing allowlist glob `skills/skill-aproda-*/**` (no manifest edit); `aldc.local.json` and any `mcp.json` must **not** be synced (developer state) — they are git-ignored via the managed block (rollout §3). Anchor at the real git root. |
| D-24 | Registration belongs in the existing extension; `#aldcConfiguration` gains the `local` block (both files, never merged). |
| D-26 | DRV keeps lifecycle ownership. Deploy prefers `al_publish` / `altool publishapp`; the deploy fallback is the direct Dev Endpoint POST on both adapters, `fkh publishapp --devScope` is no longer a deploy route (Q-18); target verification via `fkh listcontainers`, inspection via `fkh getappinfo` and recovery stay. Needs an addendum. |
| D-34 | Conflicts on AL CLI source — resolve via C-7. |
| D-39 | Extended to ASINST: every route publishes through the Dev Endpoint (Q-6); the Mgmt DLL no longer publishes. |
| D-43 | Store, prompt-on-miss and retry-once reused unchanged; only the trigger point moves to before server start (+ restart). |
| D-46 / D-47 | New skill → every catalog (`aldc.yaml`, `copilot-instructions.md`, indexes) + `aldc-validate`. |
| D-48 | Tier model reused for AL tools. |

## Documentation drift found during this review

**Done 2026-10-15 (Wave A, independent of the E-010 rollout).** Evidence: installed AL Language extension
18.1.2842859 `package.json` (`contributes.languageModelTools`) + AL MCP `tools/list` (Q-5).

- `docs/copilot-reference.md`: tool inventory corrected — `al_symbolrelations` and `al_getnextobjectid` exist as
  VS Code LM tools since AL 18.1; AL MCP row lists the measured 16 tools and is callable once registered;
  new *Call name vs. reference name* (`name: al_getdiagnostics`, `toolReferenceName: al_get_diagnostics` —
  the old "typo" claim was wrong for frontmatter); AL-extension-registered MCP servers (Troubleshooting,
  Profiling, Snapshot); `altool` CLI verbs; MCP build cache finding (Q-2); `al-symbols-mcp` unique value reduced.
- Frontmatter: `ms-dynamics-smb.al/al_symbolrelations` added to al-developer, al-implement-subagent,
  al-planning-subagent, al-architect, al-review-subagent, dredd, al-triage, al-agent-builder, al-spec.create,
  al-agent.create/.task/.test; `ms-dynamics-smb.al/al_getnextobjectid` to al-developer, al-implement-subagent,
  al-agent-builder, al-spec.create, al-agent.create (the agents/prompts that create objects). al-architect also
  gained `al_symbolsearch`, which its prose already used without the grant. `al_get_diagnostics` stays.
- Prose: al-developer *tool_boundaries* (new tools; `al_build`/`al_publish` "not granted here" instead of "no such
  tool"), al-implement-subagent *tool_boundaries* (ID allocation, spec IDs win), al-architect, al-spec.create
  (IDs via `al_getnextobjectid`).
- Nonexistent tool names removed: `al-build.prompt.md` (`al_incremental_publish`, `al_package`,
  `al_publish_existing_extension`, `al_full_package` → `al_publish` parameters), `al-context.create.prompt.md`
  (`al_generatepermissionset`, `/al-test`), `docs/agents/index.md`, `docs/agents/al-developer.agent.md`,
  `docs/framework/ai-native-instructions-architecture.md`.
- `aldc-validate`: compliant (2 pre-existing warnings, unrelated).

**Verify once in VS Code:** reload, open *Configure Tools* for al-developer and al-spec.create and check that
`al_symbolrelations` and `al_getnextobjectid` are listed as enabled — requires AL Language ≥ 18.1 on every
workstation; on older versions the entries resolve to nothing (harmless, but missing).

**Not changed (deliberately):**

- `claude-plugin/**`, `.claude/**`, `packages/foundation/**` — Claude runtime and package mirrors, not maintained
  by Aproda (`CLAUDE.md` ownership note); their "ALTool has no publish/test verb" remains outdated there.
- Upstream skills that say `al_build` generically (skill-api, -copilot, -events, -migrate, -pages, -performance,
  -permissions, -testing, -debug): route selection is owned centrally (DRV *Build route* + copilot-reference);
  rewriting nine upstream skills would add D-2 merge points for no behavioural gain.
- Instructions: none names an AL tool — nothing to change.

## Tool surface — Wave B (with the E-010 rollout)

Prerequisite: `al-mcp` registered (Phase 3) and its frontmatter qualification measured (Q-5) — until then
**no** `al-mcp` entry in any `tools:` list. Placeholder below: `<al-mcp>/<tool>`.

| File | Add | Why / gate |
|---|---|---|
| `agents/al-developer.agent.md` | `<al-mcp>/al_compile`, `/al_build`, `/al_getpackagedependencies`, `/al_inspectpage` (Tier 1); `/al_publish`, `/al_run_tests` (Tier 2); `aprodaag.aproda-aldc/startAlMcp` | Level 1 inner loop with `projectPath`; Tier 2 only with complete target bundle (C-2) and environment acknowledgement; phase 4c |
| `agents/al-implement-subagent.agent.md` | `<al-mcp>/al_compile`, `/al_build` | Build proof per phase with `projectPath`; no publish/test — that is the conductor's DRV gate; phase 4c |
| `agents/al-conductor.agent.md` | `aprodaag.aproda-aldc/startAlMcp` only | It owns the once-per-session start question; deploy/test stay in the DRV engine |
| `agents/al-triage.agent.md` | `<al-mcp>/al_run_tests` (Tier 2), `/al_compile` | Reproduce a failure with one codeunit; HITL per Tier 2 |
| `agents/dredd.agent.md` | candidate `<al-mcp>/al_compile` with analyzers | Static evidence without producing an `.app`; decide in phase 4c (Dredd is read-only on code — compile does not write) |
| `agents/al-review-subagent.agent.md`, `al-planning-subagent`, `al-architect` | nothing | Read-only roles; no build/run |
| `agents/al-translate-subagent.aproda.agent.md` | `<al-mcp>/al_searchtranslations`, `/al_writetranslation` — **E-005 decides** | Overlaps E-005 tooling |
| `prompts/al-build.prompt.md` | rewrite to the nested fallback (`al-mcp` → DRV) instead of VS Code `al_build`/`al_publish` | Affected by E-009 (prompt-file migration) — do it once, in the migrated form; phase 4c |
| `skills/skill-aproda-deploy-run-verify/SKILL.md` (D-16) | *Build route*: new route "`<al-mcp>` `al_build`/`al_compile {projectPath}` after the Base → `Test/.alpackages` refresh"; engine route 1 internally `altool compile` → `alc.exe`; *Target adapter* table: Dev Endpoint for ASINST; test-run routing, result classification, deploy fallback (see *Routing*) | Engine parts phase 4b, level-1 route phase 4c |
| `skills/skill-aproda-al-mcp/SKILL.md` (new, D-16) | tool tiers, C-1/C-2, session flow, starter | Phase 2 |
| `skills/skill-aproda-aldc/SKILL.md` (D-16) | Step 2 conventions: frontmatter segment = `toolReferenceName`; verify against `package.json` / picker | Next layer change |
| `skills/skill-testing/SKILL.md` (upstream) | one pointer: single codeunit → `al_run_tests`, batches → DRV | Optional, one line |
| `docs/copilot-reference.md` | qualified `al-mcp` frontmatter names (after Q-5); tier table pointer | Phase 4c |
| `tools/aldc-validate` | new rule `agentToolNames`: check `ms-dynamics-smb.al/*` entries against an allow-list of `toolReferenceName`s in `aldc.yaml` (from the AL `package.json`), flag `al_getdiagnostics` in frontmatter and unknown names | Prevents the next silent-absence case; phase 4c |
| `.github/copilot-instructions.md`, catalogs | new skill per D-46 | Phase 4c |

## Out of scope

- **Automation API instead of the Mgmt DLL** — answered *no* for OnPrem (Q-14); the Mgmt DLL stays for ASINST
  read and cleanup.
- **Entra (`AAD`/`MicrosoftEntraID`) implementation** — branch and clear stop only (see *Authentication*), Q-12.

## Pre-step — DRV engine bugfixes (before Phase 1)

Defects in today's DRV engine that Phase 0 surfaced. They hurt current users **independently of E-010**, so
they are fixed first, as a small, separately approved Aproda-layer change (D-16), with their own release.
Scope is deliberately minimal: no E-010 routing, no new routes, no new config keys. Code references:
`skills/skill-aproda-deploy-run-verify/scripts/AprodaDeployRunVerify.psm1` as of 2026-10-15.

### B-1 — Client-DLL version gate rejects every BC `<major>.<minor>` target with minor > 0

| Aspect | Detail |
|---|---|
| Symptom | DRV test run on Fkh (BC `28.3.52162.53362`) stops: *Runner version mismatch: '…' carries BC 28.0 but the target environment is BC 28.3*. No test runs. |
| Evidence | Fkh container's own `Microsoft.Dynamics.Framework.UI.Client.dll` = `28.0.53322.0`; CH DVD 28.0–28.6 client DLLs all `28.0.*`. With an in-memory major-only override the Fkh runner ran `59010..59013` 23/23 (15.7 s). ASINST (`28.0.50938.0`) is unaffected only because its minor is 0. |
| Root cause | `Resolve-DeployRunVerifyRunner` reduces both sides with `ConvertTo-DeployRunVerifyMajorMinor` and throws on `$rv -ne $target`. The DLL `ProductVersion` keeps minor `0` for the whole major, the server reports the cumulative-update minor — the comparison can never succeed for minor > 0. `Initialize-DeployRunVerifyRunner` catches the throw, re-materializes the same `28.0.*` DLLs into `<runnerDir>/28.3`, and the next resolve fails again. |
| Fix | Compare the **major** only for DLL vs target. Keep the folder convention `<runnerDir>/<target major.minor>` (D-15 layout unchanged, a 28.3 target may hold 28.0.* DLLs). Keep the hard error when majors differ. Log both full versions (server, DLL `ProductVersion`) in the run output for evidence. |
| Not in scope | Changing the folder layout, the DVD source selection (`Resolve-DeployRunVerifyClientSource` already selects by major + highest minor), or Fkh server-version detection (stays `bcVersion` from config). |
| Docs | Skill `SKILL.md`, `scripts/README.md`, `references/runner.md`, template comment for `bcVersion`: "major.minor match" → "major match". |
| Validation | Compare cases: target `28.3` / DLL `28.0.53322.0` → accept; `28.0` / `28.0.x` → accept; `29.0` / `28.0.x` → error. Live: DRV run on Fkh 28.3 **without** override 23/23; ASINST 28.0 regression 23/23. |
| Decision | Addendum to D-15. |
| Status | **Implemented 2026-10-15** (D-16 confirmed by Florian): `ConvertTo-DeployRunVerifyMajor`, major-only comparison and version log in `Resolve-DeployRunVerifyRunner`; stale `-GlueFrom` hint removed from the mismatch message; docs + template updated; D-15 addendum written. Synthetic cases 3/3 green (28.3/28.0.53322.0 accept, 28.0/28.0.50938.0 accept, 29.0/28.0.x error). **Live 2026-10-15, first attempt invalid:** ran against the project's synced engine copy (`.github/skills/…`, layer `1.2.0_aproda.17`, git-ignored), which did not yet contain the fix — Fkh 28.3 failed after 526 ms with the old `major.minor` gate; ASINST 28.0 23/23 in 19,175 ms (old engine, no regression evidence for the fix). Fix files then copied into the project's skill copy (hash-verified). **Live re-run 2026-10-15: validated** — Fkh 28.3 `UserPassword`, no override: 23/23 in 110,211 ms, log `28.0.53322.0 … accepted for target BC 28.3.52162.53362 (major match)`; ASINST 28.0 `Windows`: 23/23 in 14,913 ms (major match). **Open:** release. |

### B-2 — Missing `authentication` silently becomes `Windows`

| Aspect | Detail |
|---|---|
| Symptom | A `launch.json` configuration without `authentication` is treated by DRV as `Windows`; the AL extension treats the same configuration as `MicrosoftEntraID` (its default, IntelliSense). Two tools, two different targets' auth for one file. |
| Root cause | `Resolve-DeployRunVerifyConfig` adds `authentication = 'Windows'` when neither the config nor the `launch.json` pick supplies one. |
| Fix | Missing value → stop with a named error that tells the developer to set `authentication` explicitly. Accepted: `Windows`, `UserPassword`. `AAD` / `MicrosoftEntraID` (one value) → clear "not supported yet" stop. Unknown value → stop. No silent default. |
| Risk | Existing configurations without `authentication` stop on the next run — intended; the message names the file and the configuration. |
| Validation | Runs with explicit `Windows` (ASINST) and `UserPassword` (Fkh) unchanged green; negative runs: missing value, `AAD`, unknown value each stop before any connection. |
| Status | **Implemented 2026-10-15** (D-16 confirmed by Florian): check in `Resolve-DeployRunVerifyConfig` (error names the `launch.json` configuration and the config file; value normalized to `Windows`/`UserPassword`); `$pick` and the `authentication` property read made StrictMode-safe. Synthetic cases 6/6 green (missing, `AAD`, `MicrosoftEntraID`, unknown → stop; `Windows`, `userpassword` → accepted). **Live 2026-10-15, first attempt invalid:** same old project engine copy — missing value still became `Windows` (no connection started). **Live re-run 2026-10-15: validated** — scratch configuration without `authentication` stopped before any connection (`authentication is not set … Supported: Windows, UserPassword.`); explicit `Windows` (ASINST) and `UserPassword` (Fkh) runs green (see B-1). **Open:** release. |

### B-3 — ASINST redeploy may miss Tenant-scope versions when unpublishing *(refuted 2026-10-15 — no fix)*

| Aspect | Detail |
|---|---|
| Result | **Refuted** (read-only, TOGA): `Get-NAVAppInfo -Name 'Gustav Gerig AG Base'` lists both Tenant versions `25.0.0.156` and `25.0.0.158` also **without** `-Tenant`. Only `IsInstalled` / `SyncState` need `-Tenant default -TenantSpecificProperties`. The leftover `25.0.0.156` therefore has another cause (`NotSynced`, failed sync). |
| Observation | The engine publishes with `Publish-NAVApp -Scope Tenant -Tenant $tenant`, but its cleanup loop lists with `Get-NAVAppInfo -ServerInstance $si -Name …` and unpublishes with `Unpublish-NAVApp …` **without** `-Tenant`. Q-16 removed a Tenant-scope app only with `-Tenant default`. A plausible source of leftovers such as Base `25.0.0.156` (`NotSynced`) on TOGA. |
| Verification (read-only) | On TOGA compare `Get-NAVAppInfo -Name 'Gustav Gerig AG Base'` with and without `-Tenant default`. Only if the Tenant-scope versions are missing without `-Tenant` is B-3 confirmed. |
| Fix (if confirmed) | Add `-Tenant $tenant` to the listing and to `Unpublish-NAVApp` for Tenant-scope packages. |
| Not in scope | The policy question whether a redeploy may unpublish **all** older versions automatically (Q-16 rule: removal only after an explicit decision) belongs to phase 4b, where the ASINST publish moves to the Dev Endpoint anyway — decided there: no automatic unpublish, one-time HITL cleanup by full identity (spec §6.9). |

### Order and gate

1. D-16 confirmation for B-1 and B-2 (given 2026-10-15); B-3 refuted.
2. Implemented and live-validated 2026-10-15; decision addendum D-15 (B-1) written. **No separate release**
   (Florian, 2026-10-15): B-1/B-2 ship with the E-010 layer release (D-53 §10, rollout §1).
3. Phase 1 done (D-53) — the Phase-5 comparison of both routes runs against a working legacy
   runner instead of an override.

## Phase-0 evidence

Full report: [`AlMcpE010Phase0Evidence.md`](AlMcpE010Phase0Evidence.md) (`altool` 18.1.43, TOGA BC `28.0.50938.0`,
Fkh BC `28.3.52162.53362`; no `ForceSync`/`Recreate`/`forceUpgrade`, credentials only in child processes).

| Date | Target | Auth | Result |
|---|---|---|---|
| 2026-10-15 | both | both | **Q-13c `publishapp`** (`Synchronize`): fresh package exit 0 (ASINST 15.6 s, Fkh 9.0 s); exact-package retry exit 1, `422 duplicate package ID`. |
| 2026-10-15 | both | both | **Q-13a `runtests --testgroups`**: 59010+59013 → 25/25 in one session (ASINST 10.8 s, Fkh 3.8 s). With non-test 59011/59012 in the group: stopped after 59010, still `succeeded`/`success: true`. DRV runner, ASINST, `59010..59013`: 23/23 in 45.9 s. DRV runner, Fkh, same range: 23/23 in 15.7 s (3.5 s test execution), client DLLs extracted from the live container, **only with an in-memory major-only version override** — the unchanged engine rejects `28.3` server vs `28.0.53322` DLL. |
| 2026-10-15 | one | — | **Q-13b** shapes: green → exit 0, `success: true`; non-test only → exit 0, `total: 0`; wrong port → exit 1, `succeeded: false`, `retryable: true`. Red result not captured (no reproducible failing test; blocked without a throwaway test app). |
| 2026-10-15 | local | — | **Q-2**: neither MCP `al_build` (Test) nor `alc.exe /project:Test` refreshes the Base package in `Test/.alpackages` (hash/timestamp unchanged); both green against stale Base. |
| 2026-10-15 | Fkh | `UserPassword` | **Q-1** fallback: `al_run_tests` with only `projectPath: Test` + company resolved to the Fkh configuration in `Test/.vscode/launch.json` (no `BC_SERVER_*` target vars set). |
| 2026-10-15 | both | both | **Q-1** precedence: child-scoped `BC_SERVER_URL` (ASINST host) alone → resolver `Server=<ASINST>`, `ServerInstance=BC`, `Auth=UserPassword` from the Fkh launch config → `UserNotAuthenticatedException` (CLI and isolated MCP server). Two identical configs in reversed order → `runtests 59021 --project` picked the **first** each time (ASINST/Windows 10/10, Fkh/UserPassword 10/10). Stand-alone `altool launchmcpserver` (reduced project, Base) returned `No server connection is configured`; the VS Code-managed server with the Test project did resolve (Q-20). |
| 2026-10-15 | local | — | **C-5**: pwsh 7.6.6 parses the real `launch.json` (comments + trailing comma). |
| 2026-10-15 | Fkh | `UserPassword` | **Q-9** (approved, temporary `Error(...)` in 59020, Fkh only, reverted and verified green 13/13): CLI and MCP both exit 1 / `succeeded: false` / `TestRunFailed`, error text + AL call stack per failing method, extra blank-method failed record (11 passed, 2 failed). Mixed group 59020 red + 59021 green: session continued, 21 passed, 2 failed. |
| 2026-10-15 | ASINST | `Windows` | **Q-21**: stand-alone MCP `al_run_tests` with complete bundle (`serverUrl`, `serverInstance`, `port`, `authentication`, `tenant`) → 59021 10/10, per-method `codeunitId`/`methodName`/`status`/`output`/`durationMs`. |
| 2026-10-15 | Fkh | `UserPassword` | **Q-20**: exact `mcp.json` launcher chain run as an independent process, parameterless `al_run_tests` → `ConnectionFailed: No server connection is configured`, although the credential was supplied. Same request under VS Code succeeded. |
| 2026-10-15 | local | — | **Q-8**: VS Code registers `workbench.mcp.startServer`, `workbench.mcp.stopServer`, `workbench.mcp.restartServer`; the measuring agent had no permitted command invoker, so not executed. |
| 2026-10-15 | local | — | **Q-3**: dotnet-tool `al.exe` 18.0.41 (in `PATH`) and extension `altool.exe` 18.1.43 coexist; prototype selects by folder `LastWriteTimeUtc`, rejects ties, ignores `al.exe`; one extension folder installed. |
| 2026-10-15 | local | — | **Q-5**: AL MCP `tools/list` (exact casing): `al_addproject`, `al_getdiagnostics`, `al_run_tests`, `al_build`, `al_writetranslation`, `al_inspectpage`, `al_getpackagedependencies`, `al_auth_logout`, `al_getnextobjectid`, `al_downloadsymbols`, `al_symbolrelations`, `al_symbolsearch`, `al_publish`, `al_compile`, `al_auth_login`, `al_searchtranslations`. The qualified name for agent `tools:` frontmatter is **not** measurable outside the VS Code host. |
| 2026-10-15 | ASINST | `Windows` | **Q-14**: MS Learn — per-tenant extension install via Automation API is SaaS-only, `extensionUpload` deprecated; Automation API route under the ASINST service URL → 404. |
| 2026-10-15 | Fkh | `UserPassword` | **Q-18**: Fkh client 2026.819.2; read-only `listcontainers --all --asJson` (one matching running target with `appLabel`) and `getappinfo --asJson` (Test app installed, `Synced`). Timing with the disposable `E010 Recovery Probe` (fresh package per publish, cleaned up and verified absent): run 1 direct POST 23,247 ms vs `fkh publishapp` 2,309 ms; run 2 direct 488 ms vs Fkh 2,481 ms. Direct timed from `PostAsync`, Fkh from CLI start; build, preflight and cleanup excluded. Fkh omits `DependencyPublishingOption=Default`. A transient Fkh Function Catalog `503` hit one preflight (no publish started, excluded). |
| 2026-10-15 | TOGA | `Windows` | **Q-22**: `Get-NAVAppInfo -Tenant default -TenantSpecificProperties` → 100 records, properties `AppId`, `ExtensionDataVersion`, `ExtensionType`, `IsInstalled`, `IsPublished`, `Name`, `NeedsUpgrade`, `Publisher`, `Scope`, `ServerInstance`, `SyncState`, `Tenant`, `Version` — **no `PublishedAs`**; all Gustav Gerig records `Scope=Tenant`. |
| 2026-10-15 | Fkh | `UserPassword` | **Q-10**: MCP tool call without credentials → no `elicitation/create`, result `UnknownError` / `UserNotAuthenticatedException`. |
| 2026-10-15 | TOGA | `Windows` | **Q-16**: disposable `E010 Recovery Probe` 1.0.0.0 published via `publishapp` (Tenant, installed, synced) → `Uninstall-NAVApp -Tenant default` (installed false) → `Unpublish-NAVApp -Tenant default` (no package left). |
| 2026-10-15 | Fkh | `UserPassword` | **Q-19**: credential ASCII-only; unauthenticated read endpoints do not distinguish valid/invalid credentials — no UTF-8 evidence possible. |
| 2026-10-15 | TOGA | `Windows` | **Scope snapshot**: Base `25.0.0.156` Tenant, not installed, `NotSynced`; Base `25.0.0.158` and Test `25.0.0.58` Tenant, installed, synced. No Global-scope packages. |
| 2026-10-15 | local workstation | — | `altool` 18.1.43 (AL extension 18.1.2842859): `runtests --testgroups` and `publishapp` present; `publishapp` options = schema update mode, force upgrade, connection only (no scope); no verb lists, uninstalls or unpublishes apps. |
| 2026-10-15 | `flobi-wan-kenobi-gustavgerig-dev-deployment` (Fkh) | `UserPassword` | Direct Dev Endpoint POST (HTTPS, port 7049, credential from the Fkh DPAPI store) of the current Base app: 200. Then via `al-mcp`: codeunit 59021 on `CRONUS CH` **10/10 passed**. |
| 2026-10-15 | `TOGA_FOOD_SA_28_AG_28_CH_FKO` | `Windows` | Direct Dev Endpoint POST: `OPTIONS` 404 (no capability probe), raw octet-stream 415, multipart with an already published package 422 (duplicate package ID), multipart with a rebuilt package of the same version 200 — installed and synced. Details: [`dev-endpoint-publish-protocol.md`](dev-endpoint-publish-protocol.md). |
| 2026-10-15 | `TOGA_FOOD_SA_28_AG_28_CH_FKO` (ASINST-type NST, BC 28) | `Windows` | Via `al-mcp`: Base `25.0.0.158` published with `ForceSync`, installed, synced; Test `25.0.0.58` published, installed, synced; codeunit 59021 **10/10 passed**. Recovery: previously stuck, not-installed versions of both apps removed and re-published. `ForceSync` **dropped the removed field `SSCC Bartender Label Code` including its data** — the documented consequence of `ForceSync` (D-39: inform the user before using it). Stuck versions: **not** a scope mix — the later scope snapshot shows only Tenant-scope packages; the leftover Base `25.0.0.156` is `NotSynced` (failed sync). |

## Open questions

| # | Question |
|---|---|
| Q-1 | ~~MCP / CLI target without parameters, `BC_SERVER_URL` precedence, several configurations?~~ **Answered 2026-10-15:** first `server` configuration of the project's `launch.json` wins; `BC_SERVER_URL` replaces only the host. Rules in C-1, C-2 and *Target resolution in `altool`*. |
| Q-2 | ~~Does MCP `al_build {projectPath}` refresh `Test/.alpackages`?~~ **Answered:** no (neither MCP nor `alc.exe`); cache refresh is a mandatory step on every route. |
| Q-3 | ~~Which AL CLI?~~ **Answered 2026-10-15:** C-7 — active extension `altool`, semver ranking, dotnet `al` only as fallback with warning (measured: 18.0.41 vs 18.1.43 side by side). |
| Q-4 | ~~Name/location of the local selection; returned by `#aldcConfiguration`?~~ **Decided 2026-10-15:** `.github/aldc.local.json`; `#aldcConfiguration` returns both; `launchConfig` + server overrides leave the DRV config with this change. To be recorded in the Phase-1 decision. |
| Q-5 | Qualified name of `al-mcp` tools in agent `tools:` frontmatter. **Partly answered:** raw names measured (see *Phase-0 evidence*). **Open:** host-integrated form — measure in Phase 3 with a temporary, ignored agent file, VS Code reload and the Tools panel. Never add a guessed name (E-006 failure class, publisher-casing lesson). |
| Q-6 | ~~ASINST: Dev Endpoint or keep the engine's Mgmt-DLL deploy (`Publish-NAVApp -Scope Tenant`)?~~ **Decided 2026-10-15:** every route publishes through the Dev Endpoint; Mgmt DLL for read and cleanup only; one-time HITL cleanup per NST, decided per package by full identity (Q-22). To be recorded in the Phase-1 decision. |
| Q-7 | ~~Range → codeunit list over N MCP calls?~~ **Superseded 2026-10-15** by *Test-run routing* (batched `altool runtests`); remaining measurement in Q-13. |
| Q-8 | ~~Can the agent start/restart `al-mcp` itself?~~ **Answered 2026-10-15:** commands `workbench.mcp.startServer` / `stopServer` / `restartServer` exist; an agent needs a tool that may invoke them. Decision: a scoped extension LM tool for `al-mcp` only, not a general command runner. |
| Q-9 | ~~Enough detail for triage?~~ **Answered 2026-10-15: yes**, CLI and MCP alike (error text + AL call stack per failing method). Rules in *`runtests` result handling* and *Fallback only on invocation failure*. |
| Q-10 | ~~Does the AL MCP server prompt for missing `UserPassword` credentials?~~ **Answered 2026-10-15: no.** Without `BC_SERVER_*` credentials no `elicitation/create` or other prompt arrived; the tool returned `UnknownError` wrapping `UserNotAuthenticatedException`. The credential must be in the server process before the call (C-3). |
| Q-11 | ~~Can an extension read the configuration selected in the *Run and Debug* dropdown?~~ **Answered 2026-10-15: no.** No public API: [vscode#77138](https://github.com/microsoft/vscode/issues/77138) (get/set selected debug configuration) open in *Backlog* since 2019; [vscode#173788](https://github.com/microsoft/vscode/issues/173788) closed as *out-of-scope* (2023-12); the proposal PR [vscode#187727](https://github.com/microsoft/vscode/pull/187727) (`debug.selectedConfiguration`) closed unmerged. Reading VS Code's internal workspace state is rejected (unsupported, can break with any release). `aldc.local.json` + QuickPick stays. |
| Q-12 | Does the AL MCP server support OnPrem Entra (`primaryTenantDomain`) via `al_auth_login`, and is the token per tenant (re-login on target switch)? (measure on the first Fkh Entra container — follow-up, not blocking E-010) |
| Q-13 | ~~`runtests` / `publishapp` against BC 28?~~ **Answered** for both targets incl. red-result JSON and the web-client-runner comparison on both targets (see *Phase-0 evidence*, *`runtests` result handling*). |
| Q-14 | ~~Automation API instead of the Mgmt DLL on ASINST?~~ **Answered 2026-10-15: no** — SaaS-only per MS Learn, route 404 on ASINST. |
| Q-15 | ~~ASINST deploy fallback when `altool publishapp` is unavailable?~~ **Answered 2026-10-15:** direct Dev Endpoint multipart POST, validated with `Windows` auth on TOGA — see [`dev-endpoint-publish-protocol.md`](dev-endpoint-publish-protocol.md). |
| Q-16 | ~~Do `Uninstall-NAVApp` / `Unpublish-NAVApp` with `-Tenant` remove DEV apps cleanly?~~ **Answered 2026-10-15: yes** on ASINST (disposable `E010 Recovery Probe` 1.0.0.0, without `ClearSchema`/`DoNotSaveData`/`ForceSync`/`Recreate`): after uninstall `IsInstalled=False`, after unpublish no package left. Recovery path only after an explicit removal decision (HITL), never for healthy packages or historical artifacts. |
| Q-17 | ~~Direct Dev Endpoint POST with `UserPassword`?~~ **Answered 2026-10-15:** works on Fkh (HTTPS 7049, credential from the Fkh store) — see *Phase-0 evidence*. |
| Q-18 | ~~Fkh deploy fallback: direct Dev Endpoint POST or `fkh publishapp --devScope --syncMode Add --sync --install`?~~ **Decided 2026-10-15 (Florian): direct Dev Endpoint POST** is the single deploy fallback for both adapters (one code path, same `415`/`422` semantics, no backend hop; ordering from `appsInOrder`). `fkh publishapp --devScope` is no longer a deploy route; `fkh` stays for target verification (`listcontainers`), app-state inspection (`getappinfo`) and recovery. Performance was not a criterion; the later probe timing (2 runs, opposite winners: direct 23.2 s / 0.5 s, Fkh 2.3 s / 2.5 s) shows no winner and does not change the decision. To be recorded in the Phase-1 decision. |
| Q-19 | ~~UTF-8 Basic auth for non-ASCII credentials?~~ **Not measurable now, decided 2026-10-15:** the Fkh credential is ASCII-only; `/dev/metadata` (200) and `GET /dev/apps` (404) answer identically for valid and invalid credentials and prove nothing. The direct-POST helper **rejects non-ASCII credentials** with a clear message until a disposable non-ASCII identity can be tested against an authenticated operation. |
| Q-20 | ~~Why is a stand-alone `launchmcpserver` connectionless?~~ **Answered in effect 2026-10-15:** the VS Code MCP host supplies the connection context; the mechanism is not identified. Consequences: C-2 complete bundle per call, no script-spawned MCP server; Phase 3 verifies the extension-registered server inside VS Code. |
| Q-21 | ~~Does `al_run_tests` accept explicit target parameters?~~ **Answered 2026-10-15: yes** (complete bundle, ASINST, 10/10). C-2 covers test runs. |
| Q-22 | ~~Does `Get-NAVAppInfo -TenantSpecificProperties` expose `PublishedAs` on BC 28?~~ **Answered 2026-10-15: no** — the property is absent (TOGA, 100 records), and DEV packages also report `Scope=Tenant`. Provenance cannot be inferred from the NST; the Phase-4 cleanup lists packages by full identity and the human decides per package. No longer blocking. |
| Q-23 | Which argument do `workbench.mcp.startServer` / `restartServer` accept for a server registered by an extension's MCP server definition provider? Needed before the scoped `startAlMcp` tool and the `auto` start mode are merged (spec §4.3a, §4.7). Measure in phase 3 (spec §4.9). |
| Q-24 | Does a changed `version` of the provider-registered server (target switch) show VS Code's MCP trust dialog again? If yes, target-dependent inputs leave `version` and target switches restart through `restartServer`. Measure in phase 3 (`L-3.1`). |

## Phases

| Phase | Content | Depends on | Gate | State |
|---|---|---|---|---|
| P | **Pre-step:** DRV engine bugfixes B-1 (client-DLL version gate), B-2 (no silent `Windows` default); B-3 refuted, no fix. | — | D-16 + validation as listed in *Pre-step* | done (ships with the E-010 release) |
| 0 | **Complete 2026-10-15:** Q-1, Q-2, Q-3, Q-8, Q-9, Q-10, Q-11, Q-13, Q-14, Q-16, Q-20, Q-21, C-5, scope snapshot; Q-19 decided (reject non-ASCII); Q-18 decided (direct POST); Q-22 answered (no `PublishedAs`). Deferred, not blocking: Q-5 host form (Phase 3), Q-12 (Entra). | — | — | done |
| 1 | Decision record D-53 (Q-4, Q-6, Q-18, Q-22) + addenda D-8, D-15, D-26, D-39, D-43; D-16 confirmation; backlog → Approved. | P, 0 | HITL | done 2026-10-15 |
| 2 | `skill-aproda-al-mcp`: shared library + starter + SKILL.md; build-only path validated without any credential (spec §3). | 1 | review, `S-2.*`, `L-2.*` | next |
| 3 | Extension `0.2.0`: MCP provider (registration, start mode `auto`/`manual` for AL workspaces only, credential hook, target QuickPick writing `aldc.local.json`, restart) + scoped `startAlMcp` tool + `#aldcConfiguration` `local` block; measure Q-5, Q-23, Q-24, verify Q-20 inside VS Code (spec §4). | 2 | review, `npm test`, `S-3.*`, `L-3.*` | open |
| 4a | DRV: `aldc.local.json` as only target source (template + engine), migration errors (spec §5). | 2 | review, `S-4a.*`, `L-4a.*`, `aldc-validate` | open |
| 4b | DRV: `altool` CLI routes (`compile`, `publishapp`, `runtests --testgroups`) with capability detection and classification; direct Dev Endpoint POST as deploy fallback on both adapters (Fkh adapter drops `fkh publishapp --devScope`; Q-18); schema mode per D-39 unchanged (`fkhSyncMode`, now for both adapters); `runonly`; route report; one-time HITL cleanup per ASINST NST by full identity (Q-22) (spec §6). | 4a | review, `S-4b.*`, `L-4b.*`, `aldc-validate` | open |
| 4c | `al-mcp` as level 1: Wave B agent/skill/doc changes, `aldc-validate` rule `agentToolNames`, catalogs (D-46), D-7 register (spec §7). | 3 (Q-5, Q-23), 4b | review, `S-4c.*`, `L-4c.*`, `aldc-validate` | open |
| 5 | Migrate *Gustav Gerig AG Base* off the prototype; DRV on both targets via both routes, results compared; second-project smoke; releases (rollout). | 2–4c | HITL for publish/test | open |

## Acceptance criteria

Design §9 applies, plus:

- A missing credential leads to the Fkh prompt (extension) or to build-only plus prompt (interim) — never to
  a silently missing tool set.
- Publishing to a target other than the selected one, or with `Recreate` / `forceUpgrade`, is impossible
  without an explicit human confirmation; `ForceSync` follows D-39 (brief information, no separate confirmation).
- No process or call ever combines a host with the credential or authentication of another target: no
  partial target bundle, no partial parameter set, `UserPassword` only over HTTPS to its own host.
- DRV asks at most once per session to start `al-mcp`, falls back to the engine without further prompts,
  and records the route per step.
- A DRV run yields the same verdict **and the same totals** on both routes for the same code and target
  (blank-method records dropped).
- A grouped test run is accepted only if every requested test codeunit appears in the result; an empty or
  truncated run is never green.
- Test is never built against a stale Base: the package-cache refresh runs on every route.
- Every publish goes through the Dev Endpoint; no route calls `Publish-NAVApp`.
- With a working `altool` route, build and test touch neither K: nor the Mgmt DLL.
- Route choice follows capability detection, never a fixed BC version; a fallback is taken only on an
  invocation failure (classified by `errorDetails.code` / completeness), never on `TestRunFailed` or a
  compile/sync error.
- Failures are counted and triaged from non-empty `methodName` records only.
- The selected target exists in exactly one place (`.github/aldc.local.json`); no tracked file selects a
  target, and an old DRV config with `launchConfig`/server overrides fails with a migration message.
- `#aldcConfiguration` returns `aldc.yaml` values and the `local` block separately, with `absent`/`stale` states.
- `copilot-reference.md` states correctly how AL MCP is reachable from VS Code chat.
