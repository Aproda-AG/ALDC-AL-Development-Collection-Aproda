---
name: skill-aproda-bc-data-access
description: "Read live data of a customer's Business Central Online (SaaS) environment — cloud sandbox or production, read-only — for support cases and root-cause analysis: setup tables, documents, ledger entries, PTE and table-extension fields, system tables such as installed apps, users or report selections. Signs in through the browser (Entra), installs a session-lived read-only helper app through the Automation API, runs table queries, and removes the app with its data afterwards. Use when a diagnosis needs real customer data or setup instead of asking the user to look it up. Not for OnPrem, Fkh or Docker containers (those use skill-aproda-al-mcp / skill-aproda-deploy-run-verify). Aproda custom skill (E-012, D-55)."
---

# Skill: BC Data Access (live customer data, read-only)

> **Aproda custom skill** — E-012, decision **D-55** (see [`../../decisions.aproda.md`](../../decisions.aproda.md) and
> [`../../readme.aproda.md`](../../readme.aproda.md)). Wired into `al-triage`; any agent may load it through this
> description. Same HITL rules apply without a named agent.

## 1. Purpose and boundary

Answer support and root-cause questions with **real data of a customer's Business Central SaaS environment**:
"which report is set up for posted invoices", "which apps are installed", "which number series is nearly exhausted",
"what is in these ledger entries". Read-only — the helper app contains no write code — on **sandbox and production**.

Not covered: OnPrem / Fkh containers (later); writing data; aggregation, sorting, paging beyond 1000 rows per table.
The Microsoft Business Central MCP Server's *Data Query Tools* need BC 29 and are re-evaluated then (D-55 item 10).

## 2. When to load

- A diagnosis needs live data or setup that the code alone cannot show.
- The human would otherwise have to look data up in the web client and paste it.
- A hypothesis must be verified against real records ("do entries with X exist?").

## 3. Prerequisites

| Item | How |
|---|---|
| PowerShell 7 | the agent terminal (`pwsh`) |
| Tenant id + environment name | from a SaaS configuration in `.vscode/launch.json` (`tenant`, `environmentName`), from the BC URL (`businesscentral.dynamics.com/<tenant>/<environment>`), or ask the human. **If more than one SaaS configuration (or environment name) is a candidate, list them and ask which one — never pick one yourself.** |
| Account | the human's account (typically a GDAP partner account) with the right to manage extensions in that environment (e.g. delegated *Dynamics 365 Business Central Administrator*, `D365 EXTENSION MGT` or SUPER) |
| Skill root | `<toolkitRoot>\skills\skill-aproda-bc-data-access` — `toolkitRoot` from `#aldcConfiguration` (`.github` in a project) |

## 4. Session workflow

Every step is one terminal command. Start your answer with the skills line (`> **Skills loaded**:
skill-aproda-bc-data-access (…)`) also when no `@agent` is used. Load the library **content-based** in each call (SRP
blocks path-based script execution; never copy the script to `$env:TEMP`):

```powershell
$skill = '<toolkitRoot>\skills\skill-aproda-bc-data-access'
. ([ScriptBlock]::Create((Get-Content -LiteralPath "$skill\scripts\BcDataAccess.ps1" -Raw)))
```

| Step | Command (after loading) | Notes |
|---|---|---|
| 1 Sign in | `Connect-BcDataAccess -SkillRoot $skill -TenantId <tenant> -Environment <env>` | Opens the system browser; **the human signs in** (account picker). Prints `BCDA: LOGIN_OK expires=…`. Last fallback if the browser flow is impossible: `-DeviceCode`. |
| 2 Company | `Get-BcDataAccessCompany` | Ask the human which company if more than one is relevant. |
| 3 Acknowledge | — | Show the text of §5 and wait for an explicit yes. |
| 4 Install | `Start-BcDataAccessSession -CompanyId <id> -EnvironmentType Sandbox\|Production -Purpose '<purpose>' -Acknowledged` | `BCDA: READY` (install ≈ 1–2 min) or `BCDA: REUSE` (an earlier session left the app — tell the human). |
| 5 Query (repeat) | `Invoke-BcDataQuery -Request '<json>' \| ConvertTo-Json -Depth 10` | Returns one object per table: `tableNo`, `tableName`, **`records`** (array of rows). Format: [`references/request-format.md`](references/request-format.md); recipes: [`references/rca-recipes.md`](references/rca-recipes.md). Large results: `-OutFile <name>.json` (session folder only; returns `tableName`, `rows`, `file`). |
| 6 End | `Stop-BcDataAccessSession` | Uninstall **with data deletion** + unpublish of this app only (identity guard), session folder and token deleted. `BCDA: CLEAN … in <n> s`. |

State at any time: `Get-BcDataAccessState`. Token expired (`BCDA: TOKEN_EXPIRED`, after ~70–85 min): run step 1 again —
session and app stay.

## 5. HITL acknowledgement (D-55 item 7)

Before step 4, collect **every** value (tenant, environment, environment type, company, purpose) — ask for missing
ones first — then show the filled text and wait for a yes. **Never show it with placeholders.** The company is part
of the text, not only a separate choice:

> Install the read-only helper app **Aproda BC Data Access** into tenant `<tenant>`, environment `<environment>`
> (**`<Sandbox | ⚠️ PRODUCTION (read-only)>`**), company `<company>`, for: `<purpose>`. It reads only what your account
> may read and is removed with its data at the end of the session. Proceed?

- The **environment type is confirmed by the human** — the Automation API does not report it. Never guess; a yes on
  the filled text (type in bold) confirms it.
- Sign-in (step 1) and the company list (step 2) may run before the acknowledgement — they change nothing in the
  environment. The install (step 4) never runs before the yes.
- The acknowledgement covers the install and the guarded clean-up of this app. It does not cover anything else.
- **Stop for the human** on: any `BCDA: GUARD` message, a Dev-published or foreign package under the app id, an
  unexpected `BCDA: REUSE` in production, `BCDA: SESSION_OPEN`, an install failure.

## 6. Query rules

- One request may contain several tables; request **only the fields you need** and a small `top` while exploring.
- **Never guess field names.** For any table whose fields you have not seen in this session, run the *Find field
  names* recipe (`Field` table, filter `TableNo`) **first**, then build the request from its `FieldName` values. Field
  names are exact AL names (`"No."`, not `"No"`).
- Filters use BC filter syntax; **enum/option values by name** (`S.Invoice`), not by caption (`Verkauf - Rechnung`).
- FlowFields are calculated; FlowFilter fields are rejected; at most 1000 rows per table, no paging or sums in v1.
- **Count rows, don't derive numbers** — report `@($result[0].records).Count`, not a difference of totals.
- Errors come back verbatim as `BCDA: QUERY_ERROR …` — correct the request (look the field up) and retry.

## 7. Data handling (D-55 item 8)

- Results may be shown in the chat.
- **Never write personal customer data** (names, addresses, e-mails, user names, amounts per person/customer/vendor)
  into `.github/plans/**`, `documentation/**` or any tracked file. Diagnoses cite **table, key and setup value** only.
- `-OutFile` writes into the session folder (`$env:TEMP\aproda-bcda\out`); `Stop-BcDataAccessSession` deletes it.
- The access token stays in the session folder; it is never printed. Do not read `token.txt`.

## 8. End of session

Run `Stop-BcDataAccessSession` before the case is closed or handed over. If the human ends earlier, tell them that
the app is still installed in `<environment>` and that the next session (or `Stop-BcDataAccessSession`) removes it.

## 9. Troubleshooting

[`references/troubleshooting.md`](references/troubleshooting.md) — every message of the library and of Business Central
seen in the E-012 live runs, with the fix.
