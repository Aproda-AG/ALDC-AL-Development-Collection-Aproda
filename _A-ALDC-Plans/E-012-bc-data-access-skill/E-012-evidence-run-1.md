# E-012 — Evidence report, run 1 (PARTIAL — stopped at A.3; result: Data Query Tools need BC 29)

## 0. Result and decision

- **Finding:** The Data Query Tools (`bc_data_*`) are **not available before BC 29**. The target sandbox runs BC 28 (web client `28.0.57306.0`); its MCP configuration card has the old layout (no *Server Features* section, no *Data Query Tools (Preview)* row). There is no Feature Management switch for it in the official documentation.
- **Official sources (Microsoft Learn):**
  - [Configure the Business Central MCP server](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/ai/configure-mcp-server) — *Server Features* list with *API Tools*, *Dynamic Tool Mode*, *Data Query Tools (Preview)*; "Select Activate. No additional configuration needed."
  - [Update 29.0 for Business Central 2026 release wave 2](https://learn.microsoft.com/dynamics365/business-central/dev-itpro/whatsnew/whatsnew-update-29-0) — lists "Run data queries with MCP Server" (General availability, Roadmap ID 573312).
  - Note: the docs do not state a minimum version for the *Server Features* section explicitly; "BC 29" is derived from the What's-new listing plus the observed BC 28 card.
- **Decision (Florian, 2026-11-13):** ALDC needs data access earlier than BC 29. E-012 therefore builds a **simple Entra-token solution with an API page** (custom app). Later, re-evaluate switching to the BC MCP server and Data Query Tools once BC 29 is available.
- **Not run:** Blocks B and C (connection, capability matrix). M-4 and M-5 remain open until a BC 29 environment is available.
- **Clean-up:** Done by Florian. The test configuration was removed from `Develop_Integration_TogaFood`; no MCP configuration is left over from this run (Block D.1).

## 1. Header

| Item | Value |
|---|---|
| Date | 2026-11-13, ~15:25–15:45 (CET) |
| VS Code | 1.144.0 (Copilot Chat version not determinable from CLI) |
| Harness / mode | Local, agent mode |
| Account type | GDAP partner (Florian signed in himself) |
| Environment | `Develop_Integration_TogaFood` (Florian confirmed this name; the brief's `Develop_Toga_Integration` was not used) |
| Environment type | Sandbox (banner: "Dies ist eine Sandkastenumgebung, die ausschliesslich Test-, Demo- oder Entwicklungszwecken dient.") |
| BC version | Web client build `28.0.57306.0` (taken from client request URLs; *Help → About* not opened) |
| UI language | German (de-CH captions) |
| Company shown | TOGA FOOD SA (company name in URL: `Toga Food AG`) |
| Configuration name | **`ALDC Data Access`** (Florian's choice; deviates from the brief's `ALDC-E012-DataQuery`) |

## 2. Setup recipe (Block 0.3 – A.3)

| # | Where | Action | Result | Browser tool | Duration |
|---|---|---|---|---|---|
| 0.3 | Browser | `openBrowserPage` on `https://businesscentral.dynamics.com/<tenant>/Develop_Integration_TogaFood` | Microsoft sign-in page | `openBrowserPage` | – |
| 0.3b | Sign-in | Credentials / MFA | Done by Florian; BC home "TOGA FOOD SA" opened | Florian manually | – |
| 0.4 | `?page=8350` | `navigatePage` with URL | Page caption "MCP-Serverkonfigurationen (Model Context Protocol)"; columns Name, Beschreibung, Aktiv, Standard, Dynamischer Werkzeugmodus, Weitere Objekte entdecken; actions Neu, Löschen, (Kopieren appears once a row exists); list empty | `navigatePage` | – |
| A.1 | Page 8350 | Click **Neu** | Card 8351 "MCP-Serverkonfiguration (Model Context Protocol)" opens; actions Kopie, Überprüfen, Erweitert, Weitere Optionen | `clickElement` by `ref` (the `selector` option did not work: BC content lives in an iframe) | – |
| A.2 (attempt 1) | Card 8351 | `typeInPage` Name and Beschreibung in parallel with `ref` | **Failed:** text of both calls ended up in *Beschreibung*; BC auto-saved a record with **empty Name**; *Bearbeitungswerkzeuge entsperren* was **On** (disabled) on that saved record; card greyed out | `typeInPage` | – |
| A.2 (clean-up) | Card 8351 | Delete icon ("Informationen löschen") → confirm **Ja** | Empty record deleted, list empty again (Florian approved) | `clickElement` | – |
| A.2 (attempt 2) | Card 8351 | **Neu**; Name field is focused → `typeInPage` without `ref` "ALDC Data Access" → `Tab` | Record saved (bookmark in URL), *Bearbeitungswerkzeuge entsperren* **Off**, *Aktiv* **Off** | `typeInPage` (text only, then key `Tab`) | – |
| A.2b | Card 8351 | `clickElement` on *Beschreibung* (ref), `typeInPage` text, `Tab` | Description saved: "ALDC E-012 test - read-only Data Query Tools" | `clickElement`, `typeInPage` | – |
| A.3 | Card 8351 | Look for *Server Features* / **Data Query Tools (Preview)** | **Not present.** The card has only: *Name, Aktiv, Standard, Dynamischer Werkzeugmodus, Weitere Objekte entdecken (disabled), Beschreibung, Bearbeitungswerkzeuge entsperren* and a *Verfügbare Tools* grid (columns API-Objekttyp [Page/Query], Objekt-ID, Objektname, API-Version, Lesen/Erstellen/Ändern/Löschen/Gebundene Aktionen zulassen) | `readPage` | – |
| A.6 (peek) | Card 8351 → *Erweitert* | Opened the menu only | Contains only **Verbindungszeichenfolge**. **No Export / Import** action visible (Block A.7 not possible in this version) | `clickElement` | – |

Recipe learnings for browser automation:
- BC content is in an iframe; use `ref` values from `readPage`, never CSS selectors.
- Type into BC fields **sequentially**, one `typeInPage` at a time. Click the field first (or use the auto-focused field), type with **no `ref`**, then press `Tab` to commit. Typing with a `ref` right after a re-render lands in the wrong field.
- BC auto-saves the new record on the first committed field. Entering the Name first avoids saving an empty-name record.
- `Escape` on the card closes the card and returns to the list.

## 3. Connection (Block B)

Not run (blocked at A.3).

## 4–5. Capability matrix / working AL queries (Block C)

Not run.

## 6. Limits & gaps found so far

- On BC `28.0.57306.0` (German UI, sandbox) the MCP configuration card has **no *Server Features* section and no Data Query Tools switch**. The documented Data Query Tools (`bc_data_*`) therefore cannot be activated here via the card.
- No *Export* / *Import* of the configuration in the *Erweitert* menu (only *Verbindungszeichenfolge*).
- Not yet checked: *Überprüfen*, *Weitere Optionen*, *Kopie*; tool selection via *Tools auswählen…* in the *Verfügbare Tools* grid; whether Data Query Tools are a separate feature that must be enabled elsewhere (e.g. *Feature Management*) or need a later BC build.

## 7. Answers for the plan

- **Q-9 (MCP enough for SaaS read?):** Not on BC 28. Custom app with an API page + Entra token is needed now. Revisit with BC 29.
- **M-4 (auth into a customer tenant):** Not measured.
- **M-5 (coverage of Data Query Tools):** Not measured.
- **Setup recipe automation:** Section 2 documents the browser steps up to A.3. Configuration *Export/Import* is not available on BC 28 (*Erweitert* only offers *Verbindungszeichenfolge*).

## 7b. State in the customer environment

The one acknowledged change (MCP configuration `ALDC Data Access`, inactive, *Unblock Edit Tools* off) was created during the run and **removed by Florian afterwards**. No other configuration was touched.

## 8. Data check

No personal data in this report or in any file created by the run.
