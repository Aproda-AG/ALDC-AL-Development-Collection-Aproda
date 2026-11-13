# Aproda BC Data Access — app source (fork-only)

> **Fork-only.** This folder is listed in `tools/aproda-sync/aproda-sync.json → neverTouch` and never reaches a
> consuming project. Projects receive only the built `.app` through
> [`skills/skill-aproda-bc-data-access/assets/`](../../skills/skill-aproda-bc-data-access/assets/).
> Decision: **D-55** in [`.github/decisions.aproda.md`](../../.github/decisions.aproda.md). Plan and evidence:
> `_A-ALDC-Plans/E-012-bc-data-access-skill/`.

## What it is

A small per-tenant extension that the skill `skill-aproda-bc-data-access` installs into a customer's Business Central
SaaS environment for one support session, queries through its API page, and removes again (uninstall with data
deletion + unpublish). It reads any table the signed-in user may read and returns JSON.

| Item | Value |
|---|---|
| App | `Aproda BC Data Access`, publisher `Aproda AG`, id see `app/app.json` |
| Minimum | application `25.4.0.0`, runtime `14.0`, target `Cloud` |
| Object IDs | 91050–91099, suffix ` DA APD`, namespace `Aproda.BCDataAccess` |
| API | `aproda/bcDataAccess/v1.0`, entity set `dataRequests` (POST `{"id":"<guid>","request":"<json>"}`) |
| Origin | the reader and API page of Konstantin Prell's Relesta prototype; signature, sandbox gate and system-table block removed (D-55) |

## Rules for changes

1. **No write code.** Forbidden in `app/src/**`: `Insert`/`Modify`/`Delete`/`Rename`/`ModifyAll`/`DeleteAll` on any
   non-temporary record, `Permissions`, `InherentPermissions`, `Commit`, `[EventSubscriber]`, `HttpClient`. The only
   table is `TableType = Temporary`. Checked by `tests/powershell/BcDataAccess.Tests.ps1` (S-12.L4).
2. **Every change = new version.** Raise `version` in `app/app.json`, build, run `Update-BcDataAccessAsset.ps1`. The app
   **id never changes** — the skill's identity guard matches it.
3. **Tested code stays as measured.** The API page's `OnInsertRecord` pattern (`Rec.Insert(false); exit(false)` with a
   client-sent `id`) and the reader were validated in E-012 live runs 2–3.

## Build

```powershell
# 1. package cache: copy Microsoft symbols (Application, Base Application, Business Foundation, System Application,
#    System) from any project's .alpackages into app\.alpackages (git-ignored)
# 2. compile (AL Language extension's compiler)
& "$env:USERPROFILE\.vscode\extensions\ms-dynamics-smb.al-<version>\bin\alc.exe" `
    /project:"tools\aproda-bc-data-access\app" /packagecachepath:"tools\aproda-bc-data-access\app\.alpackages" `
    /out:"$env:TEMP\aproda-bcda-build\Aproda AG_Aproda BC Data Access_<version>.app"
# 3. publish into the skill (content-based: SRP blocks path-based script execution)
& ([ScriptBlock]::Create((Get-Content -LiteralPath tools\aproda-bc-data-access\Update-BcDataAccessAsset.ps1 -Raw))) `
    -RepositoryRoot (Get-Location).Path -AppFile "$env:TEMP\aproda-bcda-build\Aproda AG_Aproda BC Data Access_<version>.app"
```

Alternatively `al-mcp al_build projectPath=<fork>\tools\aproda-bc-data-access\app` (E-012 run 2).

> **Not tested by decision (2026-11-13):** a build against BC 25.4 symbols. Version `1.0.0.0` was built against
> BC 28.3 symbols; it uses only objects that exist since BC 25 (`RecordRef`, `AllObjWithCaption`, `Field`,
> `Temp Blob`, `Base64 Convert`, JSON types).
