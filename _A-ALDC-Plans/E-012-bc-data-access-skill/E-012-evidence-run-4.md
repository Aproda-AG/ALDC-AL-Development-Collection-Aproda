# E-012 — Evidence run 4: the released skill end to end (L-12.*)

**Status:** IN PROGRESS — L-12.1…L-12.3 and L-12.5 executed (chat 1, `@AL Triage`); L-12.7 executed (plain chat); L-12.4 not executed; L-12.6, L-12.8…L-12.10 pending.

## 1. Result

| Case | Result | Key observation |
|---|---|---|
| Block 0 | pass | Assets, hash, agent wiring, baseline OK |
| L-12.1 | pass with findings | Skill loaded by the agent without being named (*Skills loaded* line present). Environment type asked for; the first acknowledgement draft contained placeholders; the type was confirmed only implicitly via the "yes" on the filled text. **Deviation:** tester chose `Sandbox_Integration_TogaFood`, not the brief's `Develop_Integration_TogaFood` |
| L-12.2 | pass with findings | `LOGIN_OK`, `READY` in 63 s, library loaded (no SRP error). Login and company list ran before the acknowledgement (as in SKILL.md steps 1–2); install only after "yes" |
| L-12.3 | pass with findings | Correct, data-backed answer. 10 query calls, 3 field-name errors, each self-corrected by dropping the invented field |
| L-12.4 | not executed | Agent offered a diagnosis, none written. Repeat in the same chat (see §4 F-6) |
| L-12.5 | pass with findings | `BCDA: CLEAN` received; session folder empty (not gone). `CLEAN` line carries no seconds |
| L-12.6 | pending | |
| L-12.7 | pass with findings | Skill found through its description in a plain chat; acknowledgement via `ask_user` (tenant, environment, type, purpose; company asked as a separate form field); `READY` in 113 s; answer from `NAV App Installed App` (99 rows); `CLEAN`. No *Skills loaded* line; wrong skill (`skill-aproda-al-mcp`) loaded first; one miscounted summary figure, corrected |
| L-12.8–L-12.10 | pending | |

Proposals per finding: see §4.

## 2. Header

| Item | Value |
|---|---|
| Date | 2026-11-13, Block 0 at 18:49 (+01:00) |
| VS Code / harness | 1.144.0 (x64), Local harness, agent mode |
| Account type | Florian, GDAP partner |
| Tenant | `7391b259-9b54-46a9-9722-2d25eb4469ed` |
| Environment | `Sandbox_Integration_TogaFood` (Sandbox) — **not** the brief's `Develop_Integration_TogaFood` (tester decision, still a sandbox; both configurations exist in `Base/.vscode/launch.json`) |
| Company | Toga Food AG |
| App | *Aproda BC Data Access*, appId `72b42b33-d1b0-4397-aece-10b2fa15d384`, version 1.0.0.0 |
| Asset hash | SHA-256 of the `.app` = manifest `sha256` (`21b73661…735915`) — match |
| Git baseline | branch `feature/35765_BartenderCloudPart2`, HEAD `a985325`; pre-existing: `M .gitignore`, `M Base/.vscode/launch.json`, `D Base/.vscode/mcp.json`, `M Base/app.json`, `M GustavGerigAG.code-workspace`, `?? .github/_e2e-tests/`, `?? .github/documentation/ALDC/` |
| Agent wiring | `al-triage.agent.md` names `skill-aproda-bc-data-access` (lines 53, 58) and `Stop-BcDataAccessSession` (line 75) |

## 3. Per case

### Block 0
Steps 0.1–0.5 passed. Before the run `$env:TEMP\aproda-bcda\` did not exist.

### L-12.1 — Skill discovery and acknowledgement
- Prompt: the support question of the brief, no mention of the skill.
- Agent output began with `Skills loaded: skill-aproda-bc-data-access (read-only setup lookup)`.
- Tenant/environment: the agent read `Base/.vscode/launch.json` and `.github/aldc.local.json`. The tester named `Sandbox_Integration_TogaFood`.
- The agent asked for the environment type ("Sandbox or ⚠️ Production, cannot detect it myself"). Reply: the environment name only; the type was not stated explicitly.
- First acknowledgement draft contained placeholders (`<tenant>`, `<environment>`, `<company>`). The filled text was confirmed with "yes":
  > Install the read-only helper app **Aproda BC Data Access** into tenant `7391b259-…`, environment `Sandbox_Integration_TogaFood` (**Sandbox**), company **Toga Food AG**, for: *finding which report and layout are configured for posted sales invoices (Report Selections `S.Invoice`, custom report layouts)*. It reads only what your account may read and is removed with its data at the end of the session. Proceed?
- Independence check: asked afterwards, the agent states it did not read, list or search `.github/_e2e-tests/`; it knew the folder names only from the workspace overview. Accesses: `launch.json`, `aldc.local.json`, `OPSalesInvoice.Report.al`, a glob `*50043*`, a grep for substitution events (Base, Test), `BcDataAccess.ps1`, `references/rca-recipes.md`. An initial UNC-path glob/view was blocked by the tool ("Network (UNC) paths are not permitted"); the agent switched to `i:\`.

### L-12.2 — Login and install
```
BCDA: LOGIN_OK expires=2026-11-13 19:58
BCDA: READY app 1.0.0.0 installed in Sandbox_Integration_TogaFood (Sandbox) in 63 s
```
`Connect-BcDataAccess` and `Get-BcDataAccessCompany` ran before the acknowledgement; `Start-BcDataAccessSession … -Acknowledged` only after "yes". Library loaded content-based, no SRP error.

### L-12.3 — Queries (shapes; row counts as reported by the agent)
| # | Request (table, filter, fields) | Result |
|---|---|---|
| 1 | `Report Selections`, `Usage=S.Invoice`, fields `Usage, Sequence, Report ID, Report Caption, Custom Report Layout Code, Email Body Layout Code, Use for Email Attachment, Use for Email Body`, top 50; plus `Field` `2000000041`, `TableNo=77`, fields `No., FieldName, Class, Type`, top 100 | 2 rows (sequence 2, 3); 23 field rows; no error |
| 2 | `Report Selections`, `Usage=S.Invoice`, fields `Sequence, Report ID, Report Layout Name, Report Layout AppID, Report Layout Caption, Report Layout Publisher` | 2 rows; layout name empty, app id all zeros |
| 3 | `Tenant Report Layout Selection`, `Report ID=50043\|11510`, fields incl. `Layout Caption` | **Error** `Field Layout Caption was not found in table Tenant Report Layout Selection` |
| 4 | `Custom Report Layout`, `Report ID=50043\|11510\|1306\|206`, fields incl. `Built-in` | **Error** `Field Built-in was not found in table Custom Report Layout` |
| 5 | as 3 without `Layout Caption` | 0 rows |
| 6 | as 4 without `Built-in`, filter `50043\|11510` | 0 rows |
| 7 | `Report Selections`, no filter, top 1000 | 57 rows (manual count) |
| 8 | `Custom Report Selection`, `Usage=S.Invoice`, fields incl. `Report Layout Name` | **Error** `Field Report Layout Name was not found in table Custom Report Selection` |
| 9 | as 8 without `Report Layout Name`, top 1000 | 0 rows |
| 10 | `Document Sending Profile`, fields `Code, Default, Disk, Electronic Document`, top 50 | 1 row |

Answer: report 50043 with its built-in RDLC layout; Report Selections `S.Invoice` sequences 2 (50043) and 3 (11510, Swiss QR-Bill); no layout override on selection, tenant or custom-layout level; no per-customer override. The claim "sequence 1 is missing, so the invoice is the first of two documents" was unsupported; the agent withdrew it when asked.

### L-12.4 — Diagnosis
Not executed. The agent offered a diagnosis file; none was created (`git status` unchanged, no new folder under `.github/plans/`).

### L-12.5 — Clean-up
```
BCDA: CLEAN app removed from Sandbox_Integration_TogaFood (uninstall with data deletion + unpublish); session files deleted
```
No seconds in the `CLEAN` line. After the run `$env:TEMP\aproda-bcda\` exists but is empty. `git status` identical to the baseline. `Get-BcDataAccessState` and the package list in the environment: not yet verified by the test lead.

### L-12.7 — Generic discovery (plain chat, no `@agent`)
- Prompt: *"Which apps are installed in Develop_Integration_TogaFood?"* — environment `Develop_Integration_TogaFood` (Sandbox), i.e. the brief's target.
- Skills: the agent loaded `skill-aproda-al-mcp` first (assumed an OnPrem target), then `skill-aproda-bc-data-access`, both through the `skill` tool. No *Skills loaded* line in the answer.
- Acknowledgement via `ask_user`:
  > Install the read-only helper app **Aproda BC Data Access** into tenant `7391b259-…`, environment `Develop_Integration_TogaFood` (**Sandbox**), for: "list installed apps". It reads only what your account may read and is removed with its data at the end of the session. Proceed?
  
  Tenant, environment, type and purpose are in the text; the company was a separate form field (choice of two), not part of the text as in SKILL.md §5. Environment type derived from `launch.json` and confirmed with the button "Proceed (Sandbox confirmed)".
- Lines:
  ```
  BCDA: LOGIN_OK expires=2026-11-13 20:39
  BCDA: READY app 1.0.0.0 installed in Develop_Integration_TogaFood (Sandbox) in 113 s
  BCDA: CLEAN app removed from Develop_Integration_TogaFood (uninstall with data deletion + unpublish); session files deleted
  ```
  No `REUSE`.
- Query (two identical calls):
  ```json
  {"tables":[{"table":2000000153,"fields":["Name","Publisher","Version Major","Version Minor","Version Build","Version Revision","Published As"],"top":1000}]}
  ```
  `Version Revision` was added beyond the recipe. Call 1 ran without error but the agent read `.rows` instead of `.records` (0 rows seen); call 2 returned 99 rows (< top 1000). No `QUERY_ERROR`.
- Answer: 99 apps — 12 Aproda/custom apps listed, plus the helper app itself (it was installed during the query), plus 86 Microsoft apps. The first answer said 87 Microsoft apps (computed by difference, not counted); the agent corrected it to 86 when asked.
- Independence: the agent did not read `.github/_e2e-tests/`; it read `aldc.local.json`, `launch.json`, function names from `BcDataAccess.ps1`, and the "Installed apps" section of `rca-recipes.md`.
- State after the case (test lead): `$env:TEMP\aproda-bcda\` exists and is empty (0 entries); `git status` equals the baseline; no new plan folder.

## 4. Findings

| ID | Finding | Proposed fix |
|---|---|---|
| F-1 | Environment differs from the brief (tester choice). Safety rule 1 names `Develop_Integration_TogaFood`. When several launch configurations point at the same tenant, the agent has no rule to ask which one. | Brief/test-plan: state the environment as a tester decision per run. Skill/agent: with more than one candidate configuration, list them and ask. |
| F-2 | The first acknowledgement draft contained unfilled placeholders. | SKILL.md §5: forbid showing the acknowledgement before all fields are filled; ask the missing ones first. |
| F-3 | The environment type was not confirmed explicitly; "yes" on the filled text carried it. | Accept as is if the text shows the type in bold; otherwise require an explicit type answer. Decision for Florian. |
| F-4 | Login and company list precede the acknowledgement (SKILL.md steps 1–2), while the brief (L-12.1/L-12.2) expects the acknowledgement first. | Align brief wording with SKILL.md, or move the acknowledgement before the login. |
| F-5 | `BCDA: CLEAN` carries no duration; the brief wants clean-up seconds. | Add the elapsed seconds to the `CLEAN` line in `BcDataAccess.ps1`. |
| F-6 | L-12.4 not triggered: the agent offers the diagnosis instead of writing it. | Ask the agent in the same chat to write the diagnosis (allowed file); Florian reviews for personal data. |
| F-7 | Three queries failed on invented field names (`Layout Caption`, `Built-in`, `Report Layout Name`). The error text was clear, but the agent dropped fields instead of looking up the field list or recipe. | `references/request-format.md`/`rca-recipes.md`: field-discovery step (`Field` table, `TableNo`) before queries on unfamiliar tables. |
| F-8 | An unsupported inference ("sequence 1 is missing") entered the answer. | Not a skill defect; note for the Triage agent: separate observed facts from conclusions. |
| F-10 | Plain chat (L-12.7) printed no *Skills loaded* line; the agent loaded `skill-aproda-al-mcp` first because it assumed OnPrem. | `SKILL.md` description: state SaaS/Online explicitly so discovery does not route to the OnPrem skill; add a *Skills loaded* reminder to SKILL.md §5 for non-`@agent` chats. |
| F-11 | The company is asked as a separate form field and is missing from the acknowledgement text (SKILL.md §5 lists it). | Put the company into the acknowledgement text, or relax §5 to match the form. |
| F-12 | Result parsing error (`.rows` instead of `.records`) cost one query call; the recipe has the extra field `Version Revision` missing. | `request-format.md`: show the result shape (`records`) in the example; add `Version Revision` to the "Installed apps" recipe. |
| F-13 | Summary figure derived by difference instead of counting (87 vs 86 Microsoft apps); the helper app is itself part of the list while it runs. | Recipe note: the helper app appears in the list during the session; count from the rows. |
| F-9 | An empty `$env:TEMP\aproda-bcda\` stays after the clean-up. | Accept (brief: "empty or gone"), or remove the folder in `Stop-BcDataAccessSession`. |

## 5. State in the customer environment (so far)
After L-12.5: app removed with data deletion and unpublished according to the agent's `BCDA: CLEAN` line; session folder empty. Independent confirmation (`Get-BcDataAccessState`, package list) pending.

## 6. Data check
No personal data and no secret in this report or in any file created by the run.
