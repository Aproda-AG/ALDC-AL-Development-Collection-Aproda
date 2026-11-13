# e2e-05 Option 1 spike — Result run01 (Copilot CLI/SDK session, Pass 1 only)

> Run date: 2026-11-02 ~09:26–09:30 (local). Executed by an AI assistant in a Copilot CLI/SDK session with
> `cwd` = `\\?\UNC\APD-AZU-FS01\54_User_Development\Florian Köll\Gustav Gerig AG Base\.github` — **not** in
> Copilot Chat agent mode inside the Extension Development Host window.
> **Conclusion: mostly `NOT-REACHED` (setup problem). No statement about Q1–Q5 of Option 1 can be derived from this run.**

## Problem

The session does not have the tools Part B assumes (`read_file`, `list_dir`, `file_search`, `text_search`).
Its file tools (`view`, `glob`, `grep`, `create`, `edit`) are path-based: they append `aldc-bcq:/…` to the
UNC `cwd` and refuse with "Network (UNC) paths are not permitted". `grep`/`glob` fail on the UNC `cwd`
even without the custom scheme. The spike itself is active (`calls.log` exists, `root=I:\…`).
Pass 2 and Pass 3 were not started.

## Baseline (B.0.1)

| Item | Value |
|---|---|
| Project branch | `feature/35765_BartenderCloudPart2` |
| Project status | ` M Base/.vscode/launch.json`, `?? .github/documentation/e2e-05-run-option1-virtual-folder.md` (md file is new vs. A.4.2 baseline) |
| Clone `I:\Florian Köll\BCQuality-Aproda` | HEAD `d97329b`, status clean |
| Clone `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` | HEAD `d97329b`, status clean |
| Workspace file SHA-256 | `A11EF5893F09934D71CB4AD83616714E3C71E12BE1E88819903A9B880EC262B3` |
| `Base/.vscode/launch.json` SHA-256 | `EC98889798F7BACF167AC3509C01AE49B859805F0CD441DA277EF566288BB403` |
| `calls.log` | exists (`%APPDATA%\Code\User\globalStorage\aproda-spike.aldc-bcq-spike\calls.log`), 1343 lines before, 1361 after |

## Result

| ID | Result | Evidence |
|---|---|---|
| A1 | NOT-REACHED | `view` with `aldc-bcq:/skills/entry.md`, `aldc-bcq:///skills/entry.md`, `aldc-bcq://skills/entry.md`: all treated as relative path under `.github\aldc-bcq:\…` and rejected (UNC). |
| A2 | NOT-REACHED | `view aldc-bcq:/` and `glob paths=aldc-bcq:/` rejected. Only `problems` reached the provider (see A4); content not visible. |
| A3 | NOT-REACHED | No tool can read content through the URI. |
| A4 | PARTIAL | 18 new log lines, all `root=I:\Florian Köll\BCQuality-Aproda (setting:aldcBcqSpike.root)`: `stat/readFile/readDirectory aldc-bcq:/` plus `stat` of 17 root entries. Caused by `problems filePaths=["aldc-bcq:/"]`, not by A1–A3. |
| A5 | NOT-REACHED | `grep`/`glob` fail on the UNC `cwd` in general; no evidential value. |
| A6 | PASS (weak) | `al_get_diagnostics` (workspace, limit 500): 0; `problems`: "No errors found"; `al_symbolsearch "Event Audit Buffer"`: 0. Control `Customer`/Table also 0 → AL language server apparently not loaded/ready in the host; no proof of absence of a leak. |
| A7 | PASS (worthless) | `create aldc-bcq:/skills/_probe.md` / `edit aldc-bcq:/skills/entry.md` rejected by the tools before reaching the provider. Clone status unchanged, no `_probe.md`, no `.github\aldc-bcq:` directory created. Says nothing about the provider's read-only logic. |
| A8 | NOT-REACHED | Needs a URI-capable read/list tool. |
| A9 | PASS | Branch, project status, both clones (HEAD + status), workspace hash and `launch.json` hash identical to baseline. |
| A10–A13 | NOT-REACHED | Pass 2/3 not started. |

### Tool matrix

| Tool | Works on `aldc-bcq:/`? | Error text |
|---|---|---|
| `view` | rejected | "Network (UNC) paths are not permitted: …\.github\aldc-bcq:\skills\entry.md" |
| `glob` | rejected | "Network (UNC) paths are not permitted." |
| `grep` | rejected | "Network (UNC) paths are not permitted." (also without URI) |
| `create` | rejected | as `view` |
| `edit` | rejected | 'Path "aldc-bcq:/skills/entry.md" is not absolute.' |
| `problems` (`filePaths=["aldc-bcq:/"]`) | yes, reaches provider | "No errors found" |
| `al_get_diagnostics` (`filePath=aldc-bcq:/skills/entry.md`) | accepted, URI rewritten | rewritten to `file:///aldc-bcq%3A/skills/entry.md` (`rootPath` `\aldc-bcq:\skills\entry.md`); no provider access |
| `bclsp_documentSymbols` (`aldc-bcq:/community/…good.al`) | accepted | "No symbols found in this file." |
| `bcquality` (`list .`) | yes, but **not via the spike** | Lists the root correctly via the extension resolver; no new `calls.log` lines |

## What actually happened

Baseline captured; spike confirmed active. All path-based file tools treated the URI as a relative path and
refused. Only `problems` forwarded the URI to the VS Code file system. No noticeable latency on `I:\`
(18 log lines within < 0.2 s).

## Findings

- **blocker (for this run):** the session lacks the Part B tools → `NOT-REACHED`; no statement on Q1–Q5.
- **major (Q1, hint):** URI-capable tools seem to exist only in the VS Code Chat environment. CLI/SDK agents are
  path-based and cannot reach `aldc-bcq:/` → for CLI sessions Option 1 would be dead. For Chat in the Dev Host: open.
- **minor:** `problems` on `aldc-bcq:/` triggers `readFile` on a directory; the provider answered without error
  (result "No errors found").
- **minor:** the `bcquality` tool resolves the root via the resolver, not via the spike. For CLI/SDK agents it is a
  working path without any virtual folder → argument for Option 3 or the tool-based variant.
- **nit:** untracked `e2e-05-run-option1-virtual-folder.md` in the project deviates from the A.4.2 baseline.

## Open questions

- Re-run Part B in Copilot Chat agent mode inside the Extension Development Host?
- Is the AL language server active in the Dev Host? Without it A6 and M4 are not meaningful.
- Should a CLI/SDK-based run continue with only `problems` and `bcquality` as probes (no evidential value for A1–A3, A5)?
