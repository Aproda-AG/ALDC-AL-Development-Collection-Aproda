# e2e-05 Option 1 spike — Result run02 (Copilot Chat agent mode, local, Pass 1–3)

> Run date: 2026-11-02 ~09:36–09:45 (local). Executed by an AI assistant in **Copilot Chat agent mode** inside the
> Extension Development Host window (workspace folder `aldc-bcq:/` present as 4th root). Tools used: `read_file`,
> `list_dir`, `file_search`, `grep_search`, `create_file`, `replace_string_in_file`, `get_errors`, `al_getdiagnostics`,
> `al_symbolsearch`, `bclsp_codeQualityDiagnostics`, terminal.
> **Conclusion: Q1–Q5 answered positively for reading; no search/symbol/diagnostics leak (A6 re-measured with active AL language server, M2/M4 OK); A7 (read-only) is not clean at the tool level; M6 (degraded mode) still open. New UI observation: "Reveal in File Explorer" does not work on the virtual folder.**

## Baseline (B.0.1)

| Item | Value |
|---|---|
| Project branch | `feature/35765_BartenderCloudPart2` |
| Project status | ` M Base/.vscode/launch.json`, `?? …/e2e-05-run-option1-virtual-folder.md`, `?? …/e2e-05-run-option1-virtual-folder_result_run01.md`, `?? …/e2e-05-run-option1_aldcbcqspike-log.txt` (the last two are new vs. A.4.2) |
| Clone `I:\Florian Köll\BCQuality-Aproda` | HEAD `d97329b`, status clean |
| Clone `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` | HEAD `d97329b`, status clean |
| Workspace file SHA-256 | `A11EF5893F09934D71CB4AD83616714E3C71E12BE1E88819903A9B880EC262B3` |
| `Base/.vscode/launch.json` SHA-256 | `EC98889798F7BACF167AC3509C01AE49B859805F0CD441DA277EF566288BB403` |
| `calls.log` | exists, 2051 lines before Pass 1 |

## Result

| ID | Result | Evidence |
|---|---|---|
| A1 | PASS | `read_file aldc-bcq:/skills/entry.md` and `aldc-bcq:///skills/entry.md` return the file (frontmatter, headings and tail match the real 133-line file). `aldc-bcq://skills/entry.md` **rejected**: tool treats `skills` as authority → `File \entry.md does not exist`. Only the forms with 1 or 3 slashes work. No byte-level hash comparison possible through the tool (content compared visually). |
| A2 | PASS | `list_dir aldc-bcq:/` → `.git/ .github/ .gitignore .snapshots/ agent-consumption.md CODEOWNERS community/ custom/ knowledge-index.json LICENSE microsoft/ README.md SECURITY.md skills/ tools/`; `aldc-bcq:/skills` → `do.md entry.md read.md README.md write.md`. Same names/types as `Get-ChildItem` on the `I:` clone. |
| A3 | PASS | Read `aldc-bcq:/skills/entry.md` → `aldc-bcq:/skills/read.md` (picked) → `aldc-bcq:/community/knowledge/performance/avoid-growing-globals-in-singleinstance-subscribers.good.al` (codeunit 50100 "Event Audit Buffer"). All succeeded. |
| A4 | PASS | New log lines 09:20:13–09:20:17Z: every A1–A3 access (`stat`/`readFile`/`readDirectory`) carries `root=I:\Florian Köll\BCQuality-Aproda (setting:aldcBcqSpike.root)`. |
| A5 | PASS | `file_search **/avoid-growing-globals-in-singleinstance-subscribers*` → "No files found". `grep_search "Event Audit Buffer"` → 4 hits, all in the two `e2e-05-*.md` files under `.github/documentation`; none under `aldc-bcq:`. |
| A6 | PASS | **First measurement (09:36Z, AL language server not loaded) was inconclusive:** diagnostics 0, `al_symbolsearch "Event Audit Buffer"` 0, but controls (`Customer`, project `*`) also 0. **Re-measured after the maintainer activated LSP + AL extension:** control `al_symbolsearch Customer` (Table) → 3 results from `Base/SRC/Tables/*.al` (language server active); `al_symbolsearch "Event Audit Buffer"` (scope all) → 0 symbols; `al_getdiagnostics` (workspace, limit 500) → total 70 (0 error, 30 warning, 40 hint, not truncated), 0 entries with an `aldc-bcq`/`BCQuality` path (all paths under `…\Base\…`; warnings include the missing `BusinessCentral.LinterCop.dll`, unrelated). |
| A7 | **FAIL (tool level) / PASS (provider level)** | `create_file aldc-bcq:/skills/_probe.md` and `replace_string_in_file` on `aldc-bcq:/skills/entry.md` (title `… (probe)`) both reported **success**. `read_file aldc-bcq:/skills/entry.md` afterwards showed the changed title (edit visible in VS Code), `read_file …/_probe.md` → nonexistent. `calls.log`: **no write/create/delete call**, no `DENIED`. Clone: `git status --short` empty, `Test-Path …\skills\_probe.md` = False, `git diff` empty. → The edits only landed in the VS Code editor buffer (unsaved), the provider never received a write. The `entry.md` edit was reverted by an inverse edit. Whether the provider refuses `writeFile` was **not** exercised (no save happened) — see M3. |
| A8 | PASS | `read_file aldc-bcq:/../README.md` → tool normalised to `aldc-bcq:/README.md`, returned the **clone's** README (head identical; `I:\Florian Köll\README.md` does not exist); log: `stat aldc-bcq:/../README.md DENIED(ESCAPE)`. `aldc-bcq:/skills/../../x` → normalised to `/x`, nonexistent, no outside access. `list_dir aldc-bcq:/..` and `aldc-bcq:/skills/..` → tool error, log `readDirectory … DENIED(ESCAPE)` (also for `/skills/..`, which resolves inside the root — provider is conservative). Never returned content/names from outside the clone. |
| A9 | PASS | Branch, project status, both clones (HEAD + status), workspace hash and `launch.json` hash identical to baseline (checked after Pass 1, 2 and 3). No `.github\aldc-bcq:` directory created. |
| A10 | PASS | After the maintainer changed `aldcBcqSpike.root` (no reload): reads of `entry.md`, `do.md` and the `.good.al` file succeed; log 09:38:38Z `root=C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda (setting:aldcBcqSpike.root)`. |
| A11 | PASS | Workspace-file hash unchanged (`A11EF589…262B3`), `launch.json` hash unchanged, clones clean. |
| A12 | PASS (after correction) | **Attempt 1** (09:40Z): `aldcBcqSpike.root=I:\does-not-exist` but `aprodaAldc.bcquality.path` still set → provider **silently fell back** (`root=C:… (setting:aprodaAldc.bcquality.path)`), reads succeeded, no warning. **Attempt 2** (09:41Z, path blanked): `list_dir aldc-bcq:/` → `BCQuality clone not resolved (no candidate has skills\entry.md). Tried: setting:aldcBcqSpike.root=I:\does-not-exist[noEntryPoint]; setting:aprodaAldc.bcquality.path=unset[notSet]; env:BCQUALITY_HOME=unset[notSet]`. `read_file aldc-bcq:/skills/write.md` and `/skills/does-not-exist-file.md` → `Unable to read file … (Unavailable (FileSystemError): BCQuality clone not resolved …)` with the same candidate list. Log: `UNRESOLVED tried=[…]` per access. |
| A13 | PASS | Yes. The error names every tried candidate with a verdict (`noEntryPoint` / `notSet`) and uses `Unavailable (FileSystemError)`; a missing file inside a resolved clone yields the different, generic `Unable to resolve nonexistent file` (seen in Pass 1/2). |
| M1 | PASS (maintainer) | Works as expected: virtual root expands, `skills/entry.md` opens, no "unable to resolve" warning. |
| M2 | PASS (maintainer) | Works as expected: no hit from the virtual root in `Ctrl+P`, `Ctrl+T` or Search view. |
| M3 | PASS (maintainer) | Works as expected: editing/saving in the virtual root refused / read-only. `calls.log` (2954 lines) contains no `writeFile`/`NoPermissions`/delete/rename/create line at all, so the refusal happens before the provider (editor-level read-only), and the provider's own write rejection remains unexercised. |
| M4 | PASS (maintainer) | Works as expected: no Problems entry for `aldc-bcq:` (measured with active AL language server). |
| M5 | PASS (maintainer) | Works as expected: no Source Control repository for the virtual root. |
| M6 | NOT-REACHED | Degraded mode (same `.code-workspace` in a normal window without the extension) not reported; still open. |
| M7 (new) | **FAIL / limitation** | "Reveal in File Explorer" (right-click in Explorer) does not work on files/folders of the virtual root, whereas it works for normal workspace folders. Expected: the scheme `aldc-bcq:` is not a `file:` URI, so the OS shell has no path to open. |

### Tool matrix

| Tool | Works on `aldc-bcq:/`? | Notes / error text |
|---|---|---|
| `read_file` | yes | URI forms `aldc-bcq:/…` and `aldc-bcq:///…` ok; `aldc-bcq://skills/…` rejected (`File \entry.md does not exist`) |
| `list_dir` | yes | root and subdirectories; `..` → error |
| `file_search` | no hits (not indexed) | "No files found" for a file that exists in the clone |
| `grep_search` | no hits (not indexed) | no hit under `aldc-bcq:` |
| `create_file` | **reports success, nothing persisted** | no provider write call, file not readable afterwards |
| `replace_string_in_file` | **reports success, edit visible in buffer only** | no provider write call, clone unchanged |
| `get_errors`, `al_getdiagnostics`, `bclsp_codeQualityDiagnostics` | accepted, empty | AL language server not loaded |
| `al_symbolsearch` | accepted, 0 results | controls (`Customer`, project `*`) also 0 |

## What actually happened

Local Chat session reached `aldc-bcq:/` directly; reading, listing and the provider log work, no noticeable latency on
`I:\` (log entries ms apart). Pass 1 ran clean except for A7: the edit/create tools do not fail on a read-only provider
but apply to the in-memory document, so a successful tool message does not mean a persisted write. Pass 2 repointed
without reload. In Pass 3 the first attempt was masked by the next resolver rung; after blanking it the error is
explicit. During Pass 3 the first `read_file aldc-bcq:/skills/entry.md` still returned content although the log marks
the clone as `UNRESOLVED` — served from VS Code's cached/open document, not the provider (a never-opened file such as
`skills/write.md` fails correctly).

## Findings

- **major (A7):** agent edit/create tools "succeed" on `aldc-bcq:/` and leave a dirty/unsaved buffer or a phantom change; subsequent reads in the same window return the modified text. Provider-level read-only was not demonstrated (no save/`writeFile` reached it). Needs: `FileSystemProvider` + `FileSystemError.NoPermissions` on write paths **and** the workspace folder marked read-only (e.g. `files.readonlyInclude`/`isReadonly`-style filesystem capability `FileSystemProviderCapabilities.Readonly`) so editors/tools refuse up front. Re-measure with M3.
- **major (A12, attempt 1):** an explicitly configured but invalid root falls through to the next rung without any warning. A mis-set explicit setting then silently serves another clone (possibly stale or wrong version). Suggest: log/notify when a higher-priority candidate is set but invalid.
- **minor (A12):** stale content survives an `UNRESOLVED` clone for already opened documents (cache). An agent can read old text with no error.
- **minor (A8):** `aldc-bcq:/skills/..` (resolves inside the root) is denied as `ESCAPE`; harmless but over-conservative.
- **minor (A1):** URI form `aldc-bcq://…` (two slashes) is parsed with an authority; document the accepted forms (`aldc-bcq:/path`) for agent prompts.
- **minor (A5/A6):** no search/diagnostics leak (confirmed with active AL language server), but search being blind to the folder also means agents cannot discover knowledge via `file_search`/`grep_search` — they must use `read_file`/`list_dir` (or the `bcquality` tool).
- **minor (M7, UI):** "Reveal in File Explorer" does not work on the virtual root (no `file:` URI). Developers cannot jump from the knowledge base to the real clone in Windows Explorer; workaround is the path shown by *Aproda ALDC: Show BCQuality Status* / the resolved root command. Document it, or add a command (e.g. "Reveal BCQuality clone") in the real extension. Not a blocker for Option 1; it is a difference to the junction approach.
- **info (A7/M3):** M3 confirms a manual save is refused, but the refusal is editor-level (no write call reaches the provider log). Only the agent edit tools behave misleadingly (buffer-only edits).
- **nit:** two untracked files in the project (`…_result_run01.md`, `…_aldcbcqspike-log.txt`) deviate from the A.4.2 baseline.
- **info:** resolver behaves as documented: three rungs, explicit candidate list, `BCQUALITY_HOME` was `notSet` in the extension host (although set in the terminal environment).

## Open questions

- A7/M3: the provider log has no write-type call (`writeFile`/`NoPermissions`/delete/rename) at all, so the provider's own write rejection was never exercised; only the editor-level read-only was observed. Is that sufficient for the real extension, or must the provider be probed with a forced write (e.g. a test-only command)?
- M6 (degraded mode without the extension) is still to be done and compared against the workspace hash `A11EF589…262B3`.
- Should the real extension warn when an explicit root is invalid (A12 attempt 1)?
- Should the real extension offer a "Reveal BCQuality clone in Explorer" command to compensate M7?
- Settings: verified restored (`aprodaAldc.bcquality.path` = `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`, no `aldcBcqSpike.root` in `settings.json`); clones and workspace hash unchanged.
