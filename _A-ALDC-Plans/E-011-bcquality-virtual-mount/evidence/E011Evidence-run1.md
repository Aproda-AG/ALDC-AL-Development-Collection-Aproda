# E-011 — Live test evidence (phase 4)

**Status:** FINAL (2026-11-13, 18:45 CET). Junction cases (L-11.9, L-11.7) not run by decision of Florian.
**Brief:** `_e2e-tests/e-011/E-011-live-test-brief.md`; **plan:** `_e2e-tests/e-011/E-011.test-plan.md` §4.
**Rules observed:** no commit, no push; no edits to extension or layer files; temporary files only under
`Test/PowerShell/_temp/`; workspace file changed by the agent only through the approved restore in step 0.3 and the
L-11.11 fixture (end state = L-11.1 state, hash `E8D1896E…`).

## Environment

| Item | Value |
|---|---|
| Date | 2026-11-13 |
| Project / drive | Gustav Gerig AG Base, `I:\Florian Köll\Gustav Gerig AG Base` (network share `\\APD-AZU-FS01\54_User_Development`) |
| Project HEAD | `a985325` (*update launch.json*) |
| Fork HEAD | `17769e6` (*docs(E-011): live test brief (phase 4), plan status*), branch `feature/e006-bcquality` (brief requires `ff81222` or later) |
| Applied layer | `1.2.0_aproda.17`, `appliedRef` `17769e656dffb1708f8e41429c68aab5544cb85c` (from `#aldcConfiguration`) |
| VS Code | 1.144.0 (`2c33b50b16c472efe58357d1d2a8a5414bc23fbf`, x64) |
| Extension | `aprodaag.aproda-aldc@0.3.0` (before step 0.4: `0.2.1`) |
| `aprodaAldc.external.mount` | unset → default `virtual` |
| `aprodaAldc.bcquality.autoReconcile` | unset → default |
| `aprodaAldc.bcquality.path` | `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` |
| `aprodaAldc.devRoot` | `c:\_EphemeralWorkspace\Florian Köll` |
| `terminal.integrated.env.windows.BCQUALITY_HOME` (user settings) | `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (terminal only; not seen by the extension host) |
| BCQuality clone | `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda` (`resolvedFrom: setting`, `verified: true`) |
| Harness (this session) | **Copilot** |

### Workspace file snapshots (`GustavGerigAG.code-workspace`)

| Snapshot | File under `Test/PowerShell/_temp/` | SHA-256 |
|---|---|---|
| After layer migration in 0.2 (before agent backup) | `e011-workspace-before.json` | `E8D1896E6E6CF571E8BE7D88D08AF47126E0C8A0BF0FDC8DDCD46C57802B3E4D` |
| Restored from `HEAD` (baseline for L-11.1) | `e011-workspace-restored.json` | `BF783F13CFAEEC477CC2EE853A0D130D6FF7157C16B1F6A3838CCA246A1F0BC0` |
| After L-11.1 (reference for L-11.6/9/11) | `e011-workspace-after-L111.json` | `E8D1896E6E6CF571E8BE7D88D08AF47126E0C8A0BF0FDC8DDCD46C57802B3E4D` |
| L-11.11 fixture v1 (comment inside the entry object — invalid) | `e011-workspace-L1111-legacy.json` | `782877169249E527694A91BE071328EB79C17DF552CED82B51D53250F15424EF` |
| L-11.11 fixture v2 (comment line above the entry — per brief) | `e011-workspace-L1111-legacy-v2.json` | `335A2E114A80392E749A9885B70418F38F5A3E19DAB083907718B5A04B9F9D4A` |
| Final (after L-11.11) | — (working copy) | `E8D1896E6E6CF571E8BE7D88D08AF47126E0C8A0BF0FDC8DDCD46C57802B3E4D` |

`e011-workspace-HEAD.json` (hash `14207A52…`) is a `git show` export with different line endings/encoding — same
content, not used for comparisons.

## Block 0 — Preparation

| Case | Date | Project / drive | Mount | Result | Evidence (log lines, git diff, tool output) | Note |
|---|---|---|---|---|---|---|
| 0.1 | 2026-11-13 | fork, `C:` | — | done (Florian) | Fork HEAD `17769e6` | |
| 0.2 | 2026-11-13 | Gustav, `I:` | (0.2.1: junction) | **partial** | Prompt: *"Aproda ALDC will migrate this project's layout — this is one-way: GustavGerigAG.code-workspace: replaced the '.external' path root with the virtual root (aldc-external:/)."* — confirmed. Error (extension `0.2.1`): *"Aproda ALDC initialization failed: EEXIST: file already exists, symlink 'C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda' -> 'i:\Florian Köll\Gustav Gerig AG Base\.external\bcquality'"*. `.github/copilot-instructions.md:107` contains *Reaching BCQuality — access rule* ✅. `.external/README.md` does **not** mention `aldc-external:/` (unchanged, dated 2026-10-27, still describes the junction) ❌ | See D-1. EEXIST: `0.2.1` behaviour; the broken junction from E-010 run 2 existed but was invisible over SMB (`dir /a`, `Test-Path` → nothing). Layer migration ran during 0.2, i.e. before the agent backup (deviation from brief order) |
| 0.3 | 2026-11-13 | Gustav, `I:` | — | done | Backup + hashes above. `dir /a .external`: `README.md`, `SSC Bartender Beispiel setup\` (no `bcquality` visible). `git status --short`: ` M Base/.vscode/launch.json`, ` D Base/.vscode/mcp.json`, ` M Base/app.json`, ` M GustavGerigAG.code-workspace`, `?? .github/_e2e-tests/`, `?? .github/documentation/ALDC/` | The three `Base/` changes pre-date the test and are unrelated. With Florian's approval the workspace file was restored with `git checkout -- GustavGerigAG.code-workspace` so that `0.3.0` performs the migration itself (L-11.1 precondition) |
| 0.4 | 2026-11-13 | Gustav, `I:` | virtual | done (Florian) | `code --list-extensions --show-versions` → `aprodaag.aproda-aldc@0.3.0` | |
| 0.5 | 2026-11-13 | Gustav, `I:` | virtual | done | Environment table above | |

## Block A — Migration and Explorer

| Case | Date | Project / drive | Mount | Result | Evidence (log lines, git diff, tool output) | Note |
|---|---|---|---|---|---|---|
| L-11.1 | 2026-11-13 | Gustav, `I:` | virtual | **FAIL (partial)** | Log after reload 0.4:<br>`[16:32:04.392Z] Aproda ALDC extension activated.`<br>`[16:32:14.191Z] Workspace migration (GustavGerigAG.code-workspace): replaced .external path root by aldc-external:/`<br>`[16:32:14.198Z] Removed BCQuality link: i:\Florian Köll\Gustav Gerig AG Base\.external\bcquality`<br>`git diff`: only `-      "path": ".external"` / `+      "uri": "aldc-external:/"` ✅. Hash after = `E8D1896E…` (byte-identical to the layer migration in 0.2) ✅. Junction removed (`Test-Path` False, `.external` mtime 17:32) ✅. **Explorer:** root `.external` still the physical folder (hover `I:\Florian Köll\Gustav Gerig AG Base\.external`), no `bcquality/` ❌. After a second manual *Reload Window*: hover `\` (virtual root), `bcquality/` visible ✅; no new log line, workspace file unchanged (hash `E8D1896E…`, mtime 17:32:14) — reconcile idempotent ✅ | See D-2. "Comments kept" not checkable: the file has no comments (covered by L-11.11) |
| L-11.2 | 2026-11-13 | Gustav, `I:` | virtual | **FAIL** | a) `bcquality/skills/entry.md` opens from the Explorer, content shown ✅. b) edit attempt: *"Editor is read-only because the file system of the file is read-only."* ✅. c) context menu *Reveal in File Explorer (real path)* on `entry.md`: no reaction, no message, no log line ❌. d) palette *Aproda ALDC: Reveal BCQuality Clone* with nothing selected: Windows Explorer opens `C:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda\skills` with `entry.md` selected ✅; with `entry.md` or `read.md` selected in the Explorer: no reaction ❌ | See D-3. Before the second reload a)–c) were blocked by D-2 |
| L-11.6 | 2026-11-13 | Gustav, `I:` | none → virtual | **PASS** | `none` (no reload): after a short delay `bcquality/` disappears; `README.md` and `SSC Bartender Beispiel setup` remain; root stays virtual and read-only ✅. Setting removed again (default `virtual`, no reload): `bcquality/` visible again ✅. Workspace file unchanged throughout (hash `E8D1896E…`, mtime 17:32:14) ✅ | `SSC Bartender Beispiel setup` is a real folder in `.external/`; the virtual root passes real files through read-only (spec §2.3) — expected, not a defect |
| L-11.8 | 2026-11-13 | Gustav, `I:` | virtual | **FAIL** | `aprodaAldc.bcquality.path` = `I:\Florian Köll\Gustav Gerig AG Base\Test\PowerShell\_temp` (exists, no `skills/entry.md`). On the setting change (no reload) one notification + log line:<br>`[17:08:26.528Z] WARNING: aprodaAldc.bcquality.path points to I:\Florian Köll\Gustav Gerig AG Base\Test\PowerShell\_temp (noEntryPoint); BCQuality is served from c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda (devRoot).` ✅ (path, verdict, served root, source).<br>After reload: **two** notifications — (1) the warning above with *Open Settings* / *Show BCQuality Status*; (2) *"The configured BCQuality path exists at I:\Florian Köll\Gustav Gerig AG Base\Test\PowerShell\_temp, but it does not look like a BCQuality clone (missing skills/entry.md)."* with *Install / Update BCQuality* / *Later* / *Never for this project* ❌. After a further reload with the same value: both again ❌. Log of the last reload:<br>`[17:11:07.379Z] Aproda ALDC extension activated.`<br>`[17:11:21.378Z] WARNING: aprodaAldc.bcquality.path points to … (noEntryPoint); BCQuality is served from c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda (devRoot).` — notification (2) is not logged. Setting restored; no message on restore; reload done | See D-4. Procedure incident: the value was first entered into `aprodaAldc.source.forkPath` by mistake (one reload with that value; no toolkit/fork messages reported); corrected before the real L-11.8 run |

## Block B — Agent access

| Case | Date | Project / drive | Mount | Result | Evidence | Note |
|---|---|---|---|---|---|---|
| L-11.3 | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | Fresh **Local** harness session (VS Code chat; tools `aprodaAldc_bcquality`, `aprodaAldc_readConfiguration`, `read_file`): (1) `aprodaAldc_bcquality read skills/entry.md` → `"status": "ok", "operation": "read"` (12 KB, spilled to `content.json`) ✅. (2) `read_file aldc-external:/bcquality/skills/entry.md` (lines 1–3) → `---` / `kind: entry-point` / `id: entry` ✅ (three-slash fallback not needed). (3) config: `mount = virtual`, `mountUri = aldc-external:/bcquality/`, no `diskPath`, `resolvedFrom = setting`, `verified = true`, `mounted = false` ✅ | The session's own harness label was "Copilot (VS Code Copilot Chat)"; it was opened as **Local** by Florian, and its toolset (`read_file`, `aprodaAldc_*` tool names) matches the Local harness — the self-label is not reliable |
| L-11.4 (M-1) | 2026-11-13 | Gustav, `I:` | virtual | **PASS (measured)** | Fresh **Copilot** harness session (Copilot SDK; file-read tool `view`, no `read_file`): (1) `#bcquality read skills/entry.md` → `"status": "ok"`, content `---` / `kind: entry-point` / `id: entry` ✅. (2) `view aldc-external:/bcquality/skills/entry.md` and `view aldc-external:///bcquality/skills/entry.md` → both ✗ *"Network (UNC) paths are not permitted: \\?\UNC\APD-AZU-FS01\54_User_Development\Florian Köll\Gustav Gerig AG Base\.github\aldc-external:\bcquality\skills\entry.md"*. (3) `#aldcConfiguration`: `mount = virtual`, `mountUri = aldc-external:/bcquality/`, no `diskPath`, `resolvedFrom = setting`, `verified = true` ✅ | M-1 result: in the Copilot harness the URI is not readable — `view` treats `aldc-external:` as a relative path and prefixes the cwd (fresh session: UNC cwd → UNC rejection; test-driving session with `i:` cwd → *"Path i:\…\.github\aldc-external:\bcquality\skills\entry.md does not exist."*). `#bcquality` works, so the access rule (step 1) covers this harness |
| L-11.4 pre-measurement | 2026-11-13 | Gustav, `I:` | virtual | info | Test-driving Copilot session, same three calls: `#bcquality` ok; `view aldc-external:/…` and `aldc-external:///…` → *"Path i:\Florian Köll\Gustav Gerig AG Base\.github\aldc-external:\bcquality\skills\entry.md does not exist."*; `#aldcConfiguration` as above | |
| L-11.5 (M-3) | 2026-11-13 | Gustav, `I:` | virtual | **PASS** | `al_symbolsearch "Event Audit Buffer"` (scope `all`) → 0 symbols ✅. Problems (`al_get_diagnostics`, workspace): 70 entries (0 errors, 30 warnings, 40 hints), all `file:///i:/Florian Köll/Gustav Gerig AG Base/…`; 0 with `aldc-external:`, `bcquality` or `.external` ✅. Workspace search (Ctrl+Shift+F) `avoid-growing-globals`: no hit (Florian) ✅ | Meaningful negative: the clone contains `community/knowledge/performance/avoid-growing-globals-in-singleinstance-subscribers.{md,bad.al,good.al}` |

## Block C — No overwrites between developers, legacy layout

| Case | Date | Project / drive | Mount | Result | Evidence (log lines, git diff, tool output) | Note |
|---|---|---|---|---|---|---|
| L-11.9 | — | Gustav, `I:` | — | **not run** | — | Junction tests excluded by Florian's decision (2026-11-13). Partial cover: L-11.6 (mount `none`↔`virtual`) and every reload in this run left the workspace file byte-identical (`E8D1896E…`) |
| L-11.11 | 2026-11-13 | Gustav, `I:` | virtual | **FAIL** | Fixture v2 (`335A2E11…`), diff vs L-11.1 state: `+    // E-011 L-11.11: legacy BCQuality root (clone mounted directly)` above the entry; `.external`/`uri` entry replaced by `"name": "BCQuality", "path": "../../BCQuality-Aproda"`; `+    "terminal.integrated.env.windows": { "BCQUALITY_HOME": "x" }`. Reload 1 log:<br>`[17:29:10.349Z] Workspace migration (GustavGerigAG.code-workspace): removed legacy BCQuality root '../../BCQuality-Aproda'`<br>`[17:29:10.349Z] Workspace migration (GustavGerigAG.code-workspace): added aldc-external:/ root`<br>`[17:29:10.349Z] Workspace migration (GustavGerigAG.code-workspace): removed BCQUALITY_HOME from terminal.integrated.env.windows`<br>Result: legacy root replaced by the constant entry ✅, `BCQUALITY_HOME` and the empty container removed ✅, CRLF kept, no BOM ✅ — but the file is **byte-identical to the L-11.1 state** (`E8D1896E…`, `git diff --no-index` empty): the comment line was removed ❌. Reload 2: no migration line (idempotent) ✅; Explorer only now shows `.external` (virtual) instead of the stale `BCQuality` root (yellow, `!`) — D-2 reproduced | See D-5. Fixture v1 (comment inside the entry object, `78287716…`) was an agent setup error — that comment is legitimately removed with the entry; it produced the same three log lines (`17:26:02.266Z`) and the same result and is not counted. D-2 was observed in both runs |

## Block D — Local drive, junction mode

| Case | Result | Note |
|---|---|---|
| L-11.7 (+ back to `virtual`) | **not run** | Junction tests excluded by Florian's decision. Consequence: D-2 could not be checked on a local drive |

## Closing

| Case | Date | Project / drive | Mount | Result | Evidence | Note |
|---|---|---|---|---|---|---|
| L-11.10 | 2026-11-13 | Gustav, `I:` | virtual | **PASS (with note)** | `git status --short`: ` M GustavGerigAG.code-workspace` (`git diff --stat`: 1 insertion, 1 deletion — the one-time migration), plus the pre-existing unrelated ` M Base/.vscode/launch.json`, ` D Base/.vscode/mcp.json`, ` M Base/app.json`, and the untracked `?? .github/_e2e-tests/`, `?? .github/documentation/ALDC/`. `.external/`: `README.md`, `SSC Bartender Beispiel setup` (no link). User settings equal to the 0.5 state: `aprodaAldc.external.mount` unset, `bcquality.path` = clone, `source.forkPath` = fork, `devRoot` unchanged | `.external/README.md` shows no change because 0.2 did not update it (D-1). The second project (local drive) was not used. Evidence snapshots kept under `Test/PowerShell/_temp/e011-*` (git-ignored) |

## Open defects

| # | Case | Observed | Expected | Log / evidence excerpt |
|---|---|---|---|---|
| D-1 | 0.2 | *Apply Toolkit* leaves the existing `.external/README.md` unchanged (2026-10-27, describes the junction only; no `aldc-external:/`, no mount modes) | README mentions `aldc-external:/` (brief 0.2; spec X-13: README explains the three modes and the access rule) | `Select-String .external/README.md -Pattern aldc-external` → no match |
| D-2 | L-11.1, L-11.11 | After the migration write on activation, VS Code keeps the old root until a **second** manual reload; no notification/reload prompt. Seen for the `.external` path→uri migration (L-11.1) and for the legacy-root migration (L-11.11, stale `BCQuality` root with error badge) | Spec §6: *"The write in step 3 makes VS Code reload the changed root"* — Explorer shows `README.md`, `bcquality/` after the single reload | Hover on the root before reload 2: `I:\Florian Köll\Gustav Gerig AG Base\.external`; after: `\`. Hypothesis: VS Code does not pick up the workspace-file change on the SMB share (`I:`); not checked on a local drive (L-11.7 not run). Possible mitigation: after a migration write, offer *Reload Window* |
| D-3 | L-11.2 c/d | `aprodaAldc.revealExternalPath` (context menu) and `aprodaAldc.revealBcqualityClone` with an Explorer selection do nothing; no message | `revealFileInOS` on the real path behind the `aldc-external:` URI (spec §5, S-11.26) | No log line. Hypothesis from reading `src/commands/revealBcqualityClone.ts` (not verified): the code passes `Uri.file(<real path>)` to `revealFileInOS`, but when the Explorer list has focus that built-in command uses the Explorer selection (`aldc-external:` URIs) instead of its argument and silently ignores non-`file:` resources — consistent with "works with nothing selected". S-11.26 mocks the vscode API and cannot catch this. Possible fix (not applied): on Windows spawn `explorer.exe /select,"<path>"` |
| D-4 | L-11.8 | Wrong `bcquality.path`: every reload shows **two** notifications — the new A12 warning and the older *"The configured BCQuality path exists at …, but it does not look like a BCQuality clone (missing skills/entry.md)."* (install prompt) — and both reappear on every further reload with the same value | One warning per value and window naming path, verdict and served root; no second warning after another reload with the same value (brief L-11.8, S-11.13, Q-6) | `[17:11:21.378Z] WARNING: aprodaAldc.bcquality.path points to I:\…\_temp (noEntryPoint); BCQuality is served from c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda (devRoot).` (the install prompt is not logged). Hypotheses: the pre-0.3.0 install prompt was not merged with/suppressed by the A12 warning; the "once per value" memory does not survive a reload (in-memory instead of persisted state) |
| D-5 | L-11.11 | Legacy migration removes a `//` comment line that stands directly above the legacy folder entry; result is byte-identical to a file that never had the comment | Comment line kept; file equal to the L-11.1 state except for that comment (brief L-11.11, S-11.18a "comments kept") | Fixture v2 diff above; after reload `git diff --no-index Test/PowerShell/_temp/e011-workspace-after-L111.json GustavGerigAG.code-workspace` → empty, hash `E8D1896E…`. Hypothesis: the edit range for the removed array element starts at the end of the preceding element (or includes leading trivia), so the comment between `},` and `{` is deleted with the entry; S-11.18a's fixture probably has no comment in that position |

## Observations (no defect)

- O-1 (0.2): `0.2.1` fails with `EEXIST` because a broken junction from E-010 run 2 existed under `.external/bcquality`
  but was not visible over SMB. `0.3.0` removed it on its first activation (`Removed BCQuality link: …`).
- O-2 (0.2): The layer (*Apply Toolkit*) and the extension produce byte-identical migrations (`E8D1896E…`).
- O-3: Brief order 0.2 → 0.3 lets the layer migrate before the backup; the restore from `HEAD` was needed to observe
  L-11.1. Suggest swapping 0.2/0.3 in the brief.
- O-4 (L-11.6): The virtual root passes real files of `.external/` through read-only (here `SSC Bartender Beispiel
  setup`), as specified in spec §2.3.
- O-5 (L-11.3/L-11.4): Harness self-identification is unreliable (the Local session called itself "Copilot"); the
  toolset (`read_file` + `aprodaAldc_*` vs. `view` + `#bcquality`) identifies the harness.
- O-6 (L-11.8): `BCQUALITY_HOME` under `terminal.integrated.env.windows` in the user settings is not a resolver
  candidate (terminal only); the resolver correctly fell back to `devRoot`.
- O-7: Procedure incident during L-11.8 — wrong value briefly in `aprodaAldc.source.forkPath`; corrected before the
  measured run, no toolkit/fork messages reported.

## Summary

| Result | Cases | Reason |
|---|---|---|
| **Passed** | 0.1, 0.3, 0.4, 0.5 | Preparation complete |
| **Passed** | L-11.3 | Local harness: `#bcquality`, `read_file aldc-external:/…`, `#aldcConfiguration` all work |
| **Passed (measured)** | L-11.4 (M-1) | Copilot harness: `#bcquality` and `#aldcConfiguration` work; URI read via `view` fails (path-based tool) — the expected measurement |
| **Passed** | L-11.5 (M-3) | No symbol, diagnostic or search hit from `aldc-external:` |
| **Passed** | L-11.6 | `none` ↔ `virtual` switches live without reload; workspace file untouched |
| **Passed (with note)** | L-11.10 | Only the one-time migration in `git status` (plus unrelated pre-existing changes); settings restored |
| **Failed** | 0.2 (README check) | D-1 — `.external/README.md` not updated by *Apply Toolkit* |
| **Failed (partial)** | L-11.1 | Migration correct; Explorer shows the virtual root only after a second reload (D-2) |
| **Failed** | L-11.2 | Content shown and read-only ✅; *Reveal* with an Explorer resource does nothing (D-3); without argument ✅ |
| **Failed** | L-11.8 | Two notifications per reload, repeated on every reload (D-4) |
| **Failed** | L-11.11 | Legacy migration correct except that the comment line is removed (D-5); D-2 reproduced |
| **Not run** | L-11.9 | Junction tests excluded by Florian |
| **Not run** | L-11.7 | Junction tests excluded by Florian (local-drive project not used) |

**Before committing the workspace migration:** the committed file will be the L-11.1 state (`E8D1896E…`); push only
after `0.3.0` is rolled out (brief, safety rule 1).
