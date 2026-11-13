# E-012 — BC Data Access skill (read live BC data from agents)

**Status:** Phase 5 (2026-11-13) — **implemented and accepted** (Florian: "it works, good enough"). Live run 4 (§4f)
validated the shipped skill end to end through `@AL Triage` and a plain chat; remaining L-cases waived. Approved,
decision **D-55**; spec and test plan ([`E-012.spec.md`](E-012.spec.md), [`E-012.test-plan.md`](E-012.test-plan.md)).
Runs 1–3: §4c–§4e. Not released yet; polish F-30…F-36 done (§4f). Later sections (§4b–§4f) supersede parts
of §3.3 and §4.
**Origin:** Colleague proposal, built and validated in the *Relesta AG* project (author is not an ALDC core
maintainer). Source (read-only, on the project share):

- `Relesta AG\.github\skills\skill-aproda-data-access\SKILL.md` — the skill
- `Relesta AG\Base\SRC\DataAccess\*.al` — the server side (4 AL objects)
- `Relesta AG\Base\PowerShell\DataAccessApi.ps1` — the client (sign + POST, key-pair generation)

**Working name:** `skill-aproda-bc-data-access` ("BC Data Access") — it is specific to Business Central, not a
generic data-access skill (Florian, 2026-11-13).
**Governing decisions:** D-4 (net-new `skill-aproda-*`), D-8 (immutable engine in the skill + project config),
D-15/D-16 (SRP site facts, steward guardrail), D-18 (allowlist sync), D-46 (catalogs), D-48 (tiered tool
policy), D-43 (credential handling), D-51 (Aproda app sources are a fileshare). Adoption needs a **new**
D-entry (see F-1) and a D-16 confirmation.

---

## 1. What the proposal can do today

### 1.1 End-to-end flow

```
Agent ── device-code login (Entra, public client) ──► BC access token (session folder only)
      ── GET  /api/v2.0/companies ─────────────────► company id
      ── DataAccessApi.ps1: sign(timestamp \n nonce \n request) with RSA private key (outside repo)
      ── POST /api/aproda/<group>/v1.0/companies(<id>)/dataAccessRequests ──► BC
BC    ── IsSandbox? ── VerifySignature (public key in app, ±5 min) ── generic RecordRef read ──► JSON result
```

### 1.2 Server side (AL, in the customer's Base app)

| Object | Role |
|---|---|
| `table 50000 "Data Access Request ASC"` | `TableType = Temporary` carrier: timestamp, nonce, signature, result (Blob) |
| `page 50024 "Data Access API ASC"` | API page `aproda/relesta/v1.0`, entity set `dataAccessRequests`; insert-only; `OnInsertRecord` runs the request and returns the result on the record |
| `codeunit 50020 "Data Access Mgt ASC"` | Guards (sandbox only, signature), JSON parsing, generic read via `RecordRef`, value serialization, telemetry `ASCDA0001` (denied) / `ASCDA0002` (served) |
| `codeunit 50023 "Data Access Key Mgt ASC"` | RSA/SHA256/PKCS#1 verification against a public key compiled in as a `Label`; ±5 min clock window |

Capabilities of the generic reader:

- any non-system table (ID < 2000000000) by **name or number**, several tables per request;
- `fields` **mandatory** (by name or number; FlowFilter fields rejected, removed fields ignored);
- `filters` in BC filter syntax per field; `top` default and cap **1000** rows per table;
- FlowFields calculated, Options as names, Blobs as Base64, other types in XML format (`Format(..., 0, 9)`);
- runs in the caller's BC permission context (`RecRef.ReadPermission()` check); **read-only**.

### 1.3 Client side + skill

- `DataAccessApi.ps1` (PowerShell 7): `-NewKeyPair` writes the private key (outside the repo) and prints the
  public key XML for `PublicKeyTok`; the invoke mode signs and POSTs one request and returns the parsed result.
- `SKILL.md`: when to load, locating the moving parts in a project, device-code login (async + `ask_user`),
  company lookup, call, cleanup, request/response format, limits, troubleshooting table, key rotation.
  Token handling (session folder only, deleted afterwards), "never commit the private key", "do not persist
  results" and "run inline because of SRP" are already in it.

**Verdict:** a working, thought-through prototype. The skill text is close to ALDC style already. The open
work is **packaging and governance**, not the core idea.

---

## 2. Findings

Severity: 🔴 blocks adoption · 🟠 must be solved in the adoption design · 🟡 improve when porting · ⚪ note.

### 2.1 Layer / governance

| # | Sev | Finding |
|---|---|---|
| F-1 | 🔴 | **Decision-number collision.** The proposal records itself as **D-33** in the project's copy of `decisions.aproda.md`. In the fork, D-33 is *"Fkh backend URL resolves from local VS Code user settings"*. The skill links to that D-33. A local D-entry in a project is overwritten by the next sync and does not exist in the fork. → New fork D-entry (next free after E-011's reserved D-54, i.e. **D-55** tentatively). |
| F-2 | 🔴 | **Customer/person data in the skill text.** The *Relesta example* column contains a concrete tenant ID and a personal CSP sign-in account. The fork ships `skills/skill-aproda-*/**` to **every** consuming project (D-18) — these values must not enter the fork. Replace with placeholders; keep the worked example abstract. |
| F-3 | 🟠 | **Project-local `skill-aproda-*` folder.** It matches the allowlist glob, so a later sync from the fork treats it as layer content the project does not own; it survives today only because the fork has no such folder. A project-local edit is not adopted until it reaches the fork (Ground Truth §5.6). |
| F-4 | 🟠 | **Catalogs not updated (D-46).** Not in `copilot-instructions.md` Skills table / counts, `skills/index.md`, `readme.aproda.md` inventory, `docs/copilot-reference.md`. Discovery today relies on the skill description alone. |
| F-5 | 🟡 | Skill name `skill-aproda-data-access` is too generic → rename to `skill-aproda-bc-data-access` (frontmatter `name` must match the folder). |

### 2.2 Architecture / portability

| # | Sev | Finding |
|---|---|---|
| F-6 | 🔴 | **The skill depends on AL objects that live in one customer app.** ALDC ships agent primitives, not AL code. Every other project would have to copy 4 objects, re-number them, re-prefix them, generate its own key pair and change the client. There is no home for the server side yet (see Q-2). |
| F-7 | 🟠 | **The access surface ships to production.** The API page is part of the customer's Base app and therefore exists in production too; it is only *denied at runtime* (`IsSandbox`). A dev-only capability inside a production app widens the attack surface and the review scope of every customer app. |
| F-8 | 🟠 | **SaaS-only.** `EnvironmentInformation.IsSandbox()` is the only environment gate, and the auth path is Entra device code against `api.businesscentral.dynamics.com`. Aproda's main dev loop is **OnPrem containers via Fkh** (site profile, D-26, E-010) — whether `IsSandbox()` is true in a sandbox-artifact container is **unmeasured** (M-1); auth there is NavUserPassword/Fkh credentials, not Entra. |
| F-9 | 🟠 | **Client is not generic.** `DataAccessApi.ps1` hardcodes the route `aproda/relesta/v1.0`; the skill even warns about it. Per D-8 the script belongs into the skill (`scripts/`) as an immutable engine, with route/tenant/environment from project config or parameters. |
| F-10 | 🟡 | **Auth overlaps existing layer pieces.** Device-code login is hand-rolled inline. E-007 (az CLI/ADO, D-48) already establishes an `az login`; `az account get-access-token --resource https://api.businesscentral.dynamics.com` would reuse it. D-43 has a credential store for Fkh. Device-code flow is also frequently blocked by Conditional Access. → one auth adapter decision (Q-4). |
| F-11 | ⚪ | **Alternatives not yet weighed.** Standard BC API v2.0 / OData web services (no custom AL, but only exposed entities); a dedicated AL **Query**/API page per need; the Business Central MCP server (preview; exposes configured API pages as tools — to be evaluated, not assumed). The generic reader wins on "any table, any field" — that breadth is also its risk (F-7). |

### 2.3 Security / data protection

| # | Sev | Finding |
|---|---|---|
| F-12 | 🟠 | **Sandbox ≠ test data.** Sandboxes are routinely copies of production → results contain personal data. The skill says "show only what the user asked for, do not persist" — ALDC needs this as an explicit rule tied to the output-language/artifact rules (no results in `.github/plans/**`, phase reports, memory.md, ADO comments, PR bodies). |
| F-13 | 🟡 | **Nonce is not checked.** The table is temporary, so a captured request can be replayed within the ±5 min window. The signature is not bound to tenant/environment/company. Impact is low (caller still needs a valid token with read permission; read-only), but should be stated or fixed. |
| F-14 | 🟡 | **One key pair per app, private key per developer disk.** Public key compiled into the app → rotation requires a redeploy; key distribution between developers is unspecified. |
| F-15 | 🟡 | **Permission set coverage not found.** The four objects do not appear in the project's permission set files (to be verified in the project — `Access = Internal` objects and the API page still need execute/read entitlements for non-SUPER users). |

### 2.4 AL code quality (if the server side is kept)

| # | Sev | Finding |
|---|---|---|
| F-16 | 🟡 | No `SetLoadFields` on the `RecordRef` before `FindSet` — reads all columns for up to 1000 rows per table (al-performance rule). |
| F-17 | 🟡 | `Media`/`MediaSet` fall into the default branch (`Format` → GUID); acceptable but should be documented. |
| F-18 | ⚪ | Labels are `Locked = true` (English-only API errors) — consistent for an API surface; telemetry carries only table numbers and row counts (no PII) — good. |

---

## 3. Fit with ALDC

### 3.1 Where it helps

| Consumer | Use |
|---|---|
| `al-triage` | Reproduce/localize from a symptom with real data ("which entries have X?") — read-only matches its read-only contract |
| `al-developer` | Verify field values after a fix or a deploy |
| `skill-aproda-deploy-run-verify` | Optional post-run data check (out of scope for the first cut) |
| HITL validation (D-11) | Evidence for a validation issue without the user copying screenshots |

Nothing in ALDC reads live BC data today. E-010 (`al` MCP) builds/publishes/tests, Fkh transports, DRV runs
tests — none of them query records. The capability is genuinely new.

### 3.2 What ALDC must add around it

- **Tool tier + HITL (D-48 pattern):** read-only, but on personal data → proposal: Tier-1 per call, plus a
  **one-time consent per session** naming environment, company and purpose before the first query (Q-5).
- **Data-handling rule:** results stay in chat/session folder; never in persisted artifacts (F-12).
- **Skills evidencing:** consumers declare `skill-aproda-bc-data-access` like any other skill.
- **Catalogs (D-46)** and **validator (D-47)** coverage.
- **Site facts:** SRP-safe execution (scripts under the project's `.github/skills/...` on the share, D-15).

### 3.3 Target shape (proposal, to be decided in Phase 1)

```
skills/skill-aproda-bc-data-access/
├── SKILL.md                 # procedure, rules, request format, troubleshooting (placeholders only)
├── scripts/
│   ├── BcDataAccess.ps1     # engine: sign + POST; route/tenant/env as parameters (from DataAccessApi.ps1)
│   └── Get-BcAccessToken.ps1# auth adapter(s), see Q-4
└── references/
    ├── request-format.md
    └── server-side.md       # how the server side is provided (Q-2)
```

Project-local config (D-8): API route, environment, company resolution hints — in `aldc.local.json` (E-010
target selection) or a small `bc-data-access.config.jsonc`; secrets never.

---

## 4. Open questions

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q-1 | Adopt at all, or keep project-local? | (a) adopt as Aproda skill; (b) project skill `skill-relesta-*`; (c) reject in favour of standard APIs | **Decided 2026-11-13: (a), approved** (Florian; D-55). |
| Q-2 | Home of the **server side** (F-6/F-7) | (a) AL templates in `references/`, `al-developer` generates them per project (prefix/IDs/key); (b) **separate Aproda dev-tools app** ("Aproda BC Data Access"), installed in sandboxes/containers only, distributed via the Aproda app fileshare (D-51); (c) status quo: each customer Base app carries the objects | **(b)** as target — no production surface, one code base, one review; (a) as interim if (b) is not feasible soon. Needs an owner and an ID range. |
| Q-3 | Environment scope | (a) SaaS sandboxes only; (b) SaaS + OnPrem Fkh containers | Decide after **M-1** (does `IsSandbox()` hold in containers?) — (b) is where most dev work happens. |
| Q-4 | Auth adapter | (a) device code (as is); (b) `az account get-access-token` (reuse E-007 login); (c) Fkh credential store for OnPrem (D-43) | Adapter-based: (b) first, (a) fallback, (c) if Q-3 = (b). |
| Q-5 | HITL tier | (a) none (read-only); (b) consent once per session; (c) approval per query | **(b)** — personal data justifies one explicit gate without making every lookup a stop. |
| Q-6 | Signature model | (a) keep RSA + key per app; (b) key per Aproda (one dev-tools app, Q-2b); (c) drop signature, rely on a dedicated permission set | Follows Q-2: with (b) one key + nonce/environment binding (F-13). |
| Q-7 | Agent wiring | (a) description-only discovery; (b) in-place wiring of `al-triage`/`al-developer` (D-9, D-2 conflict) | **Decided 2026-11-13 (Florian): both** — generally discoverable through the skill description, **and** `al-triage` wired in place (D-9). `al-developer` not wired. |
| Q-8 | Ownership | Colleague as `AUTHORS.md` co-author; who maintains the server side? | **2026-11-13:** plan reviewed — "our plan fits" (Florian). Colleague = original author in `AUTHORS.md`; app source + skill maintained in the fork (E-012 spec). |

### Measurements

| # | What | Why |
|---|---|---|
| M-1 | `EnvironmentInformation.IsSandbox()` in an Fkh OnPrem container built from sandbox artifacts | Q-3 |
| M-2 | `az account get-access-token --resource https://api.businesscentral.dynamics.com` against an Aproda tenant (Conditional Access, CSP accounts) | Q-4 |
| M-3 | Permission set coverage for a non-SUPER user in Relesta | F-15 |

---

## 4b. Round 2 — decisions and revised direction (2026-11-13)

### Primary use case (decided)

**Analysis of customer setups and customer data to solve support cases and do root-cause analysis.** Target is
the **customer's** tenant (CSP/GDAP), not an Aproda dev tenant. Primary consumer: `al-triage`.

### Decisions (Florian)

| # | Decision |
|---|---|
| R-1 | **Name:** `skill-aproda-bc-data-access`. **SaaS first**; Fkh/OnPrem afterwards. |
| R-2 | **Login:** browser-based Entra login (like the AL extension), device code only as last fallback. Preferred: the Aproda extension obtains the token via VS Code's Microsoft auth and performs the calls, so the agent never sees the token (D-24 pattern); fallback: PowerShell browser login with WAM off. Supersedes Q-4. |
| R-3 | **Server side ships inside the skill** and lives only for the session: publish → query → unpublish. DEV or PTE mode — whichever is simpler and more sensible. Supersedes Q-2. |
| R-4 | **ID range 91050–91099**, object suffix **`DA APD`**. |
| R-5 | **Production access is wanted, strictly READ-only** (enforcement layers below). Writes possibly on sandboxes/Fkh, **never** on production — to be clarified separately (R-8). |
| R-6 | **Data handling:** Copilot Business (protected, under SLA) may process customer data. **No personal customer data persisted** in `plans/`, `documentation/`, or git. |
| R-7 | **Test targets:** Gustav Gerig and Toga sandboxes. |
| R-8 | **Fkh access** may work too, possibly writing; exact write scope open. |

### New fact: the built-in Business Central MCP Server (Microsoft, SaaS)

Microsoft ships an MCP server for BC online (`https://mcp.businesscentral.dynamics.com`, configured on page 8350
*Model Context Protocol (MCP) Server Configurations*). Relevant here:

- Entra sign-in; the signed-in user's BC permissions apply; VS Code is a supported host.
- **Data Query Tools (Preview)** — documented as **read-only**: `bc_data_find_tables`, `bc_data_get_table_schema`,
  `bc_data_get_table_relations`, `bc_data_query` (compiles and validates an AL query, optionally returns rows,
  with paging). This is a generic, join-capable, platform-enforced read path **without installing any app**.
- Must be activated once per environment in an MCP configuration (an admin setting change in the customer
  environment, no code). Preview → subject to change; SaaS only.

Sources: learn.microsoft.com → *Configure the Business Central MCP server* (§ data query tools) and
*Model Context Protocol (MCP) in Business Central overview*.

**Consequence:** for **SaaS read** the MCP Data Query Tools may make the custom app unnecessary. The custom app
stays relevant for (a) environments where the MCP configuration may not be activated or the preview is not
available, (b) Fkh/OnPrem (MCP server is online-only), (c) any later write capability. → **Q-9**.

### Revised technical direction for the custom app (if kept)

| Topic | Direction | Reason |
|---|---|---|
| Publish mode | **PTE via Automation API** (`extensionUpload` → install → uninstall → `Microsoft.NAV.unpublish`, the latter since 25.4) for sandbox **and** production; Fkh via the Dev Endpoint (D-39) | DEV extensions can only exist in sandboxes (MS Learn, *Extension types and scope*); one SaaS path is simpler than two. PTE deployment is asynchronous → measure duration (M-6). |
| Cleanup | "Ensure clean" at session start and end; uninstall + unpublish is mandatory | A crashed session must not leave the app installed, especially in production. |
| Schema | Keep the `TableType = Temporary` carrier | No SQL schema → install/uninstall leaves no data. |
| Read-only enforcement | **Layer 1 (guarantee):** the app contains no insert/modify/delete; only the fork-built binary may be published (fixed App ID + hash check in the skill). **Layer 2 (platform):** redesign the API as **GET** (`OnFindRecord` on the temporary source) with `DataAccessIntent = ReadOnly` → runs on the read replica, where writes throw. **Layer 3:** no `Permissions` property → no privilege escalation; reads under the user's permissions. | MS Learn: `ReadOnly` is a *hint* (replica not guaranteed) and can be overridden by the `Data-Access-Intent` header or page 9880 — so layer 2 alone is not a guarantee; layer 1 is. `Data-Access-Intent: ReadOnly` is only accepted on GET, so the current POST design cannot use it. |
| System tables | **Drop the blanket block** (ID ≥ 2000000000). Gate = the user's BC permissions; add a size cap for Blob/Media values instead. | RCA on setups needs `User`, `Access Control`, installed apps, sessions, etc. Secrets live in Isolated Storage, which is not a table. Viewing such tables is already possible for the same user via the web client's table viewer. |
| Signature / keys | **Drop RSA signing and key management.** | Comparable paths (standard APIs/OData, BC MCP Server, AL extension Dev Endpoint, web-client table viewer) all rely on Entra + BC user permissions; request signing is a pattern for identity-less callers (webhooks). With a session-lived app and user-scoped reads the signature adds key distribution cost (F-13, F-14) but no protection the user does not already have. |
| HITL | Publish/unpublish = change to a customer environment → **explicit approval per session** naming customer, environment (production flagged) and purpose. Queries afterwards without per-call approval. | D-48 tier pattern; production install visible to the customer in extension lifecycle telemetry. |
| Naming | Suffix ` DA APD` (7 chars incl. space) → base name ≤ 19 chars under the ALDC 26-char rule; own namespace (e.g. `Aproda.BCDataAccess`), not `ASC` | `Data Access Mgt ASC` already exists in Relesta Base → name clash if both are present. |
| Source location | AL **source in the fork** (fork-only, built by fork CI); the skill ships **only the `.app`** under `assets/` | `.al`/`app.json` under a consumer's `.github/skills/` would be picked up by `**/*.al` instructions, reviews/Dredd, DRV/AL-Go app discovery and object-ID tooling. Deliberate exception to D-51, to be stated in the new D-entry. |

### Writes (R-8) — direction, not decided

Separate capability and **separate app** ("DA APD Write") that the skill never publishes to a production
environment, plus an app-side guard (`EnvironmentInformation.IsSaaS() and IsProduction()` → error). Writes only via
`Validate` + `Modify(true)` (business logic runs), each write previewed and approved. Proposed as a follow-up
after the read path is validated.

### Data handling (R-6) — concrete rule for the skill

Query results may appear in chat and in transient files in the session folder (deleted at the end). Never in
`.github/plans/**`, `documentation/**`, any committed file, `memory.md` or phase reports; diagnoses cite record
keys and setup values, not personal data. *Proposal:* extend the rule to ADO comments and PR bodies.

### New / changed open questions

| # | Question | Recommendation |
|---|---|---|
| Q-9 | SaaS read path: BC MCP Server Data Query Tools, custom app, or both? | **Decided 2026-11-13 after run 1 (§4c): custom app now**; MCP re-evaluated when BC 29 is available. |
| Q-10 | Who may activate the MCP configuration in a customer environment, and is that an acceptable change? | **Decided 2026-11-13: ALDC may do it itself**, through the VS Code integrated browser (HITL acknowledgement per environment). |
| Q-11 | Extend the R-6 rule to ADO/PR? | **Decided 2026-11-13 (Florian): No.** R-6 covers `plans/`, `documentation/` and git. |

**Live test brief 1** (M-4, M-5, setup recipe): `Gustav Gerig AG Base/.github/_e2e-tests/e-012/E-012-live-test-brief-1.md`
— target Gustav tenant, sandbox `Develop_Toga_Integration`; evidence goes to `E-012-evidence-run-1.md` next to it.

Q-2, Q-4 and Q-6 are superseded by R-3, R-2 and the signature decision above; Q-3 by R-1; Q-5 by the HITL row.

### Additional measurements

| # | What |
|---|---|
| M-4 | VS Code Microsoft auth provider: token for `https://api.businesscentral.dynamics.com` in a customer tenant (client ID, consent, GDAP account) — R-2 |
| M-5 | BC MCP Server Data Query Tools on the Gustav/Toga sandboxes: availability (BC version), table coverage incl. system tables, joins, row limits, GDAP account — Q-9 |
| M-6 | PTE upload/install/uninstall/unpublish duration and success on Gustav/Toga sandboxes; does `Microsoft.NAV.unpublish` exist on their version (≥ 25.4) |
| M-7 | ID range 91050–91099 and the `DA APD` names are free in the Gustav and Toga apps — **Gustav Base source: free (checked 2026-11-13)**; installed third-party apps still open |

---

## 4c. Live run 1 result and decision (2026-11-13)

Evidence: [`E-012-evidence-run-1.md`](E-012-evidence-run-1.md) (run in *Gustav Gerig AG Base*, sandbox
`Develop_Integration_TogaFood`, GDAP partner account, BC web client `28.0.57306.0`, German UI).

| # | Result |
|---|---|
| E-1 | **Data Query Tools need BC 29.** On BC 28 the MCP configuration card (page 8351) has no *Server Features* section and no *Data Query Tools (Preview)* row; *Erweitert* offers only *Verbindungszeichenfolge* (no Export/Import). MS Learn *What's new 29.0* lists "Run data queries with MCP Server" (GA, roadmap 573312). |
| E-2 | BC 28 MCP offers only API pages/queries as tools — standard/custom **API objects**, not arbitrary tables. Not sufficient for setup/RCA analysis (custom PTE tables, system tables). |
| E-3 | **Browser recipe works** for BC page automation via the VS Code integrated browser (with caveats below). GDAP partner sign-in into the customer tenant worked (Florian manually). |
| E-4 | Blocks B/C not run → **M-4 and M-5 remain open**. The test configuration was removed afterwards; nothing left in the customer environment. |

Integrated-browser learnings for BC (reusable for any BC page automation in the skill):

- BC content is in an iframe → use `ref` values from `readPage`, never CSS selectors.
- Type **sequentially**: click the field (or use the auto-focused one), `typeInPage` **without** `ref`, then `Tab` to
  commit. Parallel or `ref`-targeted typing after a re-render lands in the wrong field.
- BC auto-saves a new record on the first committed field → fill the primary key / Name first.
- Sign-in (credentials/MFA) is always done by the human.

### Decision (Florian, 2026-11-13) — supersedes Q-9

**The tool is needed before BC 29.** E-012 builds the **custom app** (API page + Entra token, the session-lived
publish → query → unpublish flow of §4b). The **BC MCP Server + Data Query Tools are re-evaluated** once BC 29
is available on a test environment (trigger: first Aproda-reachable BC 29 sandbox; then rerun brief 1 Blocks B/C
for M-5 and decide whether the custom app stays as fallback for < 29 and Fkh/OnPrem only).

### Consequences for the custom app

| Topic | Consequence |
|---|---|
| Minimum BC version (**Q-12**) | **Decided 2026-11-13 (Florian): BC 25.4** is the lowest supported version (`application 25.4.0.0`, `runtime 14.0`). Build once against it in fork CI. |
| Unpublish | `Microsoft.NAV.unpublish` exists from **25.4** = the floor → uninstall + unpublish is always available. |
| Lifecycle API | **Decided 2026-11-13 (Florian): Automation API** (`extensionUpload` → `extensionContent` → `Microsoft.NAV.upload`, `extensionDeploymentStatus`, `Microsoft.NAV.uninstall`, `Microsoft.NAV.unpublish`) — keep it simple. **Risk:** MS Learn marks `extensionUpload` as deprecated, removal planned for 2027 release wave 1; successor is the Admin Center API `pteInstall`. Re-check when that wave is announced (same time as the BC 29 MCP re-evaluation). |
| Read-only on GET (§4b layer 2) | Needs a GET-shaped API: request passed as a filter value and evaluated in `OnFindRecord` on the temporary source. Feasible only if URL length suffices for typical requests → spike in Phase 2; otherwise keep POST and rely on layer 1 (no write code + hash-checked binary). |
| Auth (R-2, M-4) | Still open and now on the critical path. Measure first with the colleague's working method (public client `1950a258-…`, BC scope) **as a GDAP partner** into the Gustav tenant, then the VS Code Microsoft auth provider route. |

**Live test brief 2:** `Gustav Gerig AG Base/.github/_e2e-tests/e-012/E-012-live-test-brief-2.md` — M-4 (browser
login with auth code + PKCE as GDAP partner), M-6 (Automation API install/uninstall/unpublish, repeatability with the
same version), M-7 (installed-app inventory), read-capability matrix with a throw-away prototype (`DA APD`,
91050–91099, no signature, no sandbox gate, no system-table block) built in a scratch folder outside any repo, on
`Develop_Integration_TogaFood`. Evidence → `E-012-evidence-run-2.md` next to it.

---

## 4d. Live run 2 result (2026-11-13)

Evidence: [`E-012-evidence-run-2.md`](E-012-evidence-run-2.md) (GDAP partner, `Develop_Integration_TogaFood`, BC 28,
prototype `ab23bc15-…`, versions 1.0.0.0–1.0.0.3; all uninstalled and unpublished afterwards).

| # | Measurement | Result |
|---|---|---|
| M-4 | Auth | ✅ **Solved.** Auth code + PKCE, system browser, `HttpListener` on `http://localhost:<port>/`, public client `1950a258-…`, scope BC `.default offline_access`. Account picker only; no consent/MFA/CA block as GDAP partner. 16 s. `scp = Financials.ReadWrite.All` covers Automation API and custom API pages. Token lifetime ≈ 84 min. |
| M-6 | Lifecycle (Automation API) | ✅ Install 56 s (upload → `Completed`), uninstall 4 s, unpublish ≈ 1.5 s/package. Same version re-uploadable after unpublish. Upgrades leave older packages **published, not installed**. Missing package → 404 `BadRequest_ResourceNotFound`. `extensionDeploymentStatus` is not filterable by name (400) → filter client-side. |
| M-7 | Conflicts | ✅ None on a tenant with 86 extensions; install is the collision check (API returns no ID ranges). |
| — | Read capability | ✅ PTE tables, table-extension fields, filters, FlowFields, system tables (`Field`, `NAV App Installed App`, `User`, `Access Control`), multi-table, 1000-row cap, clear error texts; PATCH 405 / DELETE 400. Real RCA question (report selection for posted sales invoice) answered in 2 requests. |
| — | Dev endpoint (addendum) | `al_publish` / `altool publishapp` with a finished `.app` works on sandboxes only → `publishedAs = Dev`, seconds, no polling. **Trap:** a package once uploaded via `extensionUpload` and unpublished blocks the identical package on the Dev endpoint (duplicate key in `Tenant Application Storage`). `al_publish` returns only `PublishFailed`; `altool` shows the cause. |

### Findings for the design

| # | Finding | Consequence |
|---|---|---|
| F-19 | **POST without a `Rec`-bound field does not fire `OnInsertRecord`** (201, empty `result`). Prototype had removed timestamp/nonce/signature — the only `Rec` fields the colleague's client sent; `request` is a page variable. Sending `id` restored it. *Hypothesis:* with `DelayedInsert = true` BC inserts only when a `Rec` field was set. The colleague's page was correct for his body; the regression came from removing the signature fields. | Client template **always sends `id`** (new GUID). Optional hardening later: bind `request` to a table field. |
| F-20 | 1.0.0.1 also changed `OnInsertRecord` to `exit(true)`; untested whether the original `Rec.Insert(false); exit(false)` works with `id`. | Return to the colleague's tested pattern + `id`; verify once (minimal-change rule for tested code). |
| F-21 | `AddLoadFields` rejects FlowFields (400). | Only `FieldClass::Normal` (fixed in 1.0.0.2). |
| F-22 | Route returned 404 directly after a fresh install (R.2); length of the delay unknown. | Readiness retry (poll a trivial query until not 404, with timeout) — measure. |
| F-23 | Ensure-clean must handle **all** packages of the app id (one per version) and tolerate 404. | Engine: list by `id`, uninstall installed one, unpublish every package. |
| F-24 | Gaps for RCA: no aggregation (`CalcSums`/count), no sorting/`SetCurrentKey`, no offset paging beyond `top`. Ledger tables hit the cap quickly (≈ 132 B/row for 5 fields). | Backlog for v2 of the app (not needed for v1). |
| F-25 | Not exercised: Blob > 64 KB, Media/MediaSet, non-admin user with only `DA APD Exec`, telemetry read-back. | Test plan (Phase 2). |

### Open questions from run 2

| # | Question | Decision |
|---|---|---|
| Q-13 | Install path: Automation API only, or Dev endpoint for sandboxes too? | **Decided 2026-11-13 (Florian): Automation API only.** The skill does not use the Dev endpoint / `al_publish`. |
| Q-14 | Refresh token: store, or re-login after ≈ 84 min? | **Decided 2026-11-13 (Florian): re-login after ≈ 84 min.** Nothing persisted. |

### Further decisions (Florian, 2026-11-13)

| # | Decision |
|---|---|
| R-9 | **Clean-up deletes app data** ("sync mode Clean"). In SaaS this is `Microsoft.NAV.uninstallAndDeleteExtensionData` (the Automation API `schemaSyncMode` only knows `Add`/`Force Sync`); it cannot be undone. → **Identity guard is mandatory** before every uninstall/unpublish: app id, name, publisher and `publishedAs = PTE` must match; any mismatch aborts without a call. |
| R-10 | **The client always sends `id`** in the POST body (F-19). |
| R-11 | Test **many queries in a row without unpublish** (session use) before the spec. |

**Live test brief 3:** `Gustav Gerig AG Base/.github/_e2e-tests/e-012/E-012-live-test-brief-3.md` — one install,
~40 queries over ~20 min (bursts, duplicates, same id, no id, 5 parallel, 5/10-min idle, error in the middle, large
results), readiness after install (F-22), F-20 (colleague's original insert pattern + `id`, version `1.0.1.0`),
guarded clean-up with `uninstallAndDeleteExtensionData` incl. a negative guard test, optional re-install.
Evidence → `E-012-evidence-run-3.md`.

---

## 4e. Live run 3 result (2026-11-13) — session use and guarded clean-up

Evidence: [`E-012-evidence-run-3.md`](E-012-evidence-run-3.md) (16:45–17:12, same sandbox, version `1.0.1.0`; prototype
uninstalled with data deletion and unpublished afterwards; tenant back to 86 extensions).

| Topic | Result | Rule for the skill |
|---|---|---|
| Session use | ✅ 48 requests in ≈ 17 min (burst 27, 5 parallel, idle 5 + 10 min, error in the middle, 3 × 1000 rows): 47 × 201, 1 × 400 (intended); no 404/429/5xx; no stale read (change visible at once, restore byte-identical); p50 143 ms, p95 410 ms, max 615 ms | **One install per support session, many queries.** Sequential use without client throttling; ≤ 5 parallel calls. |
| `id` / insert pattern (F-20) | ✅ The colleague's original `Rec.Insert(false); exit(false)` works **with a client-sent `id`**; without `id` still 201 + empty `result`; a duplicate `id` is harmless (201) | Keep the colleague's tested page logic; the client always sends a new GUID (R-10). F-19/F-20 closed. |
| Readiness (F-22) | First install 0 × 404; re-install 2 × 404, first 201 after 10.7 s. Install itself 93–123 s (run 2: 56 s) | After `Completed`: retry on 404 `BadRequest_NotFound` every 5 s, max 3 min. Deployment poll timeout 10 min. |
| Clean-up with data deletion (R-9) | ✅ `Microsoft.NAV.uninstallAndDeleteExtensionData` → 204, no parameters, uninstalled after ≈ 3 s; **package stays published** → unpublish still required; re-install afterwards allowed | Ensure-clean = guarded `uninstallAndDeleteExtensionData` on the installed package + guarded `unpublish` on every package; 404 tolerated. *Data deletion itself not provable* (prototype has only a temporary table). |
| Identity guard | ✅ Blocks a foreign package. **Finding F-26:** *Data Administration (DA)* is also publisher `Aproda AG` and `PTE` → publisher + PTE alone are **not** a sufficient guard | Guard = **app id AND displayName** AND publisher AND `publishedAs = PTE`. App id is a constant of the shipped `.app`. |
| Token | Lifetime 73 min this time (run 2: 84 min) | **F-27:** re-login decision from the token's `exp` claim (with a margin, e.g. 5 min), not a fixed 84 min. Refines Q-14. |
| Dev-published copies | Guard refuses `publishedAs = Dev` → such a copy could not be cleaned by the skill | Consistent with Q-13 (Automation API only). Document as troubleshooting: remove manually in *Extension Management*. |

Script basis for Phase 3 (no secrets, outside any repo): `I:\Florian Köll\_e012-scratch\` — `Get-BcToken.ps1`,
`bc-lib.ps1`, `bc-guard.ps1`, `bc-session.ps1`, `Install-DaApp.ps1`, prototype source `DA-APD\` (1.0.1.0).

**Phase 1 technical measurements are complete for SaaS** (M-4, M-6, M-7, session use, guarded clean-up). Remaining
before approval: the review with the colleague and the open governance questions.

---

## 4f. Live run 4 result (2026-11-13) — shipped skill, accepted

Evidence: [`E-012-evidence-run-4.md`](E-012-evidence-run-4.md) (Gustav, GDAP partner; `Sandbox_Integration_TogaFood` and
`Develop_Integration_TogaFood`; app 1.0.0.0, hash verified).

| Case | Result |
|---|---|
| L-12.1 | ✅ `@AL Triage` loaded the skill **without being told** (*Skills loaded* line), asked for the environment type, showed the acknowledgement and waited |
| L-12.2 | ✅ `LOGIN_OK`, `READY` in 63 s; library loaded content-based (no SRP error) |
| L-12.3 | ✅ correct, data-backed answer to a real support question (10 queries, 3 self-corrected field-name errors) |
| L-12.5 | ✅ `BCDA: CLEAN`; nothing left in the environment, `git status` unchanged |
| L-12.7 | ✅ plain chat found the skill through its description; acknowledgement via `ask_user`; `READY` 113 s; 99 apps; `CLEAN` |
| L-12.4, L-12.6, L-12.8–L-12.10 | **waived** by Florian ("it works, good enough") — covered by synthetic tests S-12.16 (reuse), S-12.21 (token expiry), S-12.25/S-12.L2 (data handling) |

**Acceptance (Florian, 2026-11-13):** the skill works end to end; no further live tests.

### Polish items (not blocking; skill text/library only — the app is unaffected)

**Status 2026-11-13:** F-30…F-35 **done** (SKILL.md, `request-format.md`, `rca-recipes.md`, `BcDataAccess.ps1`; tests S-12.27 and S-12.L1 extended, 34/34 green); F-36 documented in SKILL.md §5; F-37 accepted; F-38 deferred.

| # | Run-4 ID | Item | Proposed change |
|---|---|---|---|
| F-30 | F-2, F-11 | Acknowledgement shown with placeholders once; company sometimes outside the text | SKILL.md §5: fill every field first; company inside the text |
| F-31 | F-1 | Several launch configurations for one tenant → no rule to ask | SKILL.md §3: list SaaS candidates from `launch.json` and ask |
| F-32 | F-7, F-12 | Invented field names; `.rows` vs `.records` | SKILL.md §6 + `request-format.md`: look up fields via the `Field` recipe for unfamiliar tables; show the result shape |
| F-33 | F-10 | Plain chat loaded `skill-aproda-al-mcp` first; no *Skills loaded* line | description: "Business Central **Online/SaaS**"; §4: print the *Skills loaded* line |
| F-34 | F-13 | Helper app counted in app lists | `rca-recipes.md`: note that *Aproda BC Data Access* appears while the session runs; count rows |
| F-35 | F-5, F-9 | `CLEAN` without seconds; empty session folder stays | library: duration in `CLEAN`, remove the empty folder |
| F-36 | F-4 | Login before acknowledgement vs. brief wording | keep (login is not a change to the environment); document in SKILL.md §5 |
| F-37 | F-3 | Type confirmed implicitly by "yes" on the filled text | accept (type is shown in bold in the text) |
| F-38 | F-8 | Unsupported inference in an answer | note for `al-triage`: separate observed facts from conclusions (no change now) |

---

## 5. Phases

| Phase | Content | Gate |
|---|---|---|
| 0 | Analysis (this document) | ✅ 2026-11-13 |
| 1 | ~~Review; open questions; live runs 2 + 3; approval; D-55~~ — ✅ 2026-11-13: plan reviewed ("fits"), Q-1/Q-7/Q-8/Q-11 decided, M-4/M-6/M-7 + session use + guarded clean-up measured (M-1 later with Fkh; M-5 with BC 29), backlog `Approved`, **D-55** recorded (D-16 confirmed) | ✅ |
| 2 | Spec + test plan: [`E-012.spec.md`](E-012.spec.md), [`E-012.test-plan.md`](E-012.test-plan.md) — drafted 2026-11-13. Not tested by decision: a user with only `DA APD Exec`; a build against BC 25.4 symbols | HITL |
| 3 | Port the skill: rename, placeholders (F-2), engine into `scripts/` (F-9), auth adapter (Q-4), data-handling + tier rules (F-12, Q-5), catalogs (F-4) — ✅ 2026-11-13: X-03…X-14, X-16 implemented; 34/34 synthetic + layer tests green, `aldc-validate` COMPLIANT (baseline 2 warnings), sync dry run ships the skill incl. `.app` and not the app source | ✅ |
| 4 | Server side per Q-2 (separate app or templates), incl. F-13/F-16 fixes — ✅ 2026-11-13: X-01/X-02 — app `Aproda BC Data Access` 1.0.0.0 (new id), fork-only source `tools/aproda-bc-data-access/`, built 0 errors / 0 warnings (BC 28.3 symbols), asset + manifest in the skill | ✅ |
| 5 | Live validation — ✅ 2026-11-13 accepted after run 4 (§4f; remaining L-cases waived). Polish F-30…F-36 done. Open: layer release (X-15 changelog), Relesta migration note (X-17) | ✅ |

## 6. Acceptance criteria (draft)

- A consuming project gets the skill through the normal sync; no tenant/account/customer value is in it.
- An agent reads N records of a named table from a sandbox (and, if Q-3 = b, from an Fkh container) with
  one consent gate and no secret on disk outside the session folder / key file.
- The server side does not exist in any production app.
- No query result appears in any persisted artifact.
- `aldc-validate` green; all D-46 catalogs list the skill.

## 7. Non-goals

Writing or modifying BC data; production environments; replacing the standard BC APIs; bulk export.
