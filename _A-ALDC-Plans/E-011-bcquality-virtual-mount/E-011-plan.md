# E-011 — BCQuality as a virtual workspace mount (junction becomes optional)

**Status:** 2026-11-13 — phases 0–3 done (D-54; extension `0.3.0` built; layer changes committed); phase 4: live
run 1 done ([evidence](evidence/E011Evidence-run1.md)), defects D-1…D-5 fixed in extension `0.3.1` + Initialize;
retest of L-11.1, L-11.2, L-11.8, L-11.11 open ([brief](E-011-live-test-brief.md)).
**Origin:** E-006 (T-29, D-49 part 4: `.external/bcquality` junction; spike e2e-05 "Option 1") and E-010 run 2
(EEXIST for the junction on `I:`). Evidence: [`evidence/`](evidence/) (spike runs 01/02 and the provider log).
**Governing decision:** D-54 (2026-11-13) — revises D-49 parts 2 and 4.

---

## Problem

The shipped way to put BCQuality into the workspace is a directory junction `.external/bcquality` onto the
developer's clone (D-49 part 4), created automatically by the extension (`aprodaAldc.bcquality.autoReconcile`,
default `true`). It works only where the repository sits on a local NTFS volume:

- On a network share (`I:` = SMB) a junction to a local `C:` path is created without error and is **broken** —
  it resolves on the file server (E-006 e2e-05 measurement; `mklink /J` refuses, symlinks are denied).
- Node sees it inconsistently (`lstat`/`readlink` mostly `ENOENT`), so the extension tried to recreate it and
  failed with `EEXIST` (E-010 run 2, Block 0). `0.2.2` only turns that into a warning.
- Most Aproda developers work on `I:`. The default therefore fails for most users.

## Goal

| # | Goal |
|---|---|
| G-1 | Default mount = a **virtual workspace folder** `aldc-external:/` served by the Aproda extension (`FileSystemProvider`; writable since `0.3.1`, edits go to the real files). It mirrors the `.external/` concept: one subfolder per external source (today `bcquality/`, served from the resolver-verified clone). Works on any drive, no link, nothing written into the tracked workspace file when a clone moves. |
| G-1a | The `.external/` concept stays **extensible**: a new source = a new `external.<name>` block in `aldc.yaml` plus a resolver; it appears as `aldc-external:/<name>/` (virtual) or `.external/<name>` (junction) without a new scheme, setting or workspace entry. |
| G-2 | The junction stays available as a **secondary, opt-in** mount; the default is no junction. |
| G-3 | Agents use `#bcquality` **whenever it is available**; otherwise they fall back to a readable path (virtual URI, resolved clone path, junction). A path is never blocked. |
| G-4 | The automatic reconcile **migrates** existing projects (junction layout → virtual mount) without manual steps; a stale junction is removed as a link only. |
| G-5 | A command opens the real clone in the OS file explorer (the virtual folder cannot "Reveal in File Explorer"). |

Non-goals: changing the resolver precedence (D-49 part 1); the `#bcquality` tool itself; search/symbol
providers for the virtual folder (proposed API — the absence of search is wanted, see evidence A5/A6/M2).

## Evidence (spike e2e-05, 2026-11-02)

| Run | Session | Result |
|---|---|---|
| run01 | Copilot CLI/SDK session (path-based file tools) | `aldc-bcq:/` **not reachable** (tools treat it as a relative path; UNC cwd refused). `#bcquality` worked via the resolver. |
| run02 | Copilot Chat, Local harness, Extension Development Host | Read/list/consumption chain **PASS** on `I:` and `C:`; provenance through the provider; **no** search/symbol/diagnostics leak (AL language server active); repoint without reload; workspace file untouched; explicit error when unresolved. Findings: A7 edit tools write into the editor buffer only; A12 an invalid explicit root silently falls through to the next rung; M6 degraded mode not measured; M7 no "Reveal in File Explorer". |

Spike code (`e2e-05-spike/`) and the run instructions were never committed and are gone; the design is in the
run reports and the provider log. The provider is rebuilt in the extension, not ported.

Findings triage (Florian, 2026-11-13): **A7** acceptable (still register the provider read-only — it costs
nothing); **M6** out of scope, the extension is a prerequisite; **M7** → extension command (G-5);
**A12** → warning (Q-6). The Copilot-harness reach stays a measurement (M-1).

## Decisions (phase 0)

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q-1 | Setting name and scope | (a) `aprodaAldc.bcquality.mount`; (b) `aprodaAldc.external.mount` for the whole `.external` concept; (c) both | **Decided 2026-11-13: (b)** `aprodaAldc.external.mount` = `virtual` (default) / `junction` / `none`, scope `application`. A per-source override only if a later source needs a different mount. |
| Q-2 | Role of `aprodaAldc.bcquality.autoReconcile` | (a) keep as the master switch for **all** automatic maintenance of the chosen mount (virtual: workspace entry + migration; junction: link; both: `BCQUALITY_HOME`); (b) split into per-mount switches | **Decided 2026-11-13: (a)**; the description changes, the name stays (no settings migration). `autoFixWorkspacePath` stays the deprecated alias. |
| Q-3 | Access rule for agents (G-3) | ordered fallback, see *Access rule* below | **Decided 2026-11-13:** ordered fallback as below; replaces the "dual path" wording of D-49 part 2 in `copilot-instructions.md` and the four consumer agents. |
| Q-4 | Scheme and root shape | (a) `aldc-bcq:/` = clone root (spike); (b) `aldc-external:/` with one folder per source | **Decided 2026-11-13: (b)** — `.external/` stays extensible (G-1a). BCQuality is `aldc-external:/bcquality/…`; the root also passes through the real files of `<repo>/.external/` (Q-5). |
| Q-5 | Workspace layout in virtual mode | (a) the `.external` root points to `aldc-external:/`, which mirrors the real folder; (b) keep the `.external` path root and add a second, virtual root | **Decided 2026-11-13: (a).** The real `<repo>/.external/` folder stays in every mode (README, junction links). VS Code cannot mount a virtual folder *inside* a `file:` folder, so the workspace root `.external` (same name) points to `aldc-external:/`, whose content mirrors the real folder: its real files passed through read-only (today `README.md`) plus one virtual folder per source (`bcquality/`). Explorer view is unchanged (`.external` → `README.md`, `bcquality/…`). In junction mode the root points back to the real folder. In virtual mode the disk path `.external/bcquality/…` does not exist — agents use the access rule. |
| Q-6 | Invalid explicit root (A12) | (a) warn once when a higher-priority candidate is set but invalid; (b) leave as is | **Decided 2026-11-13: (a)** — a mis-set path otherwise serves another (possibly stale) clone silently. |
| Q-7 | `aldc.yaml → external.bcquality.home` | (a) keep `.external/bcquality` as the static last rung (valid in junction mode only); (b) empty it | **Decided 2026-11-13: (a)**, with the comment updated: the value matters only in junction mode; the resolver answers first everywhere. |
| Q-8 | Mount `none`: what happens to the `.external` workspace root | (a) keep it as a plain path root (real folder: README only); (b) remove it from the workspace | **Decided 2026-11-13: (a)** — the `.external` root stays in every mode; same workspace shape everywhere, and the README explains how to mount BCQuality. |
| Q-9 | The mount is per workstation, the workspace file is tracked: may the entry depend on the mount? | (a) constant `uri` entry in every mode, the mount only changes what the provider shows and whether a junction exists; (b) entry per mode (Q-5/Q-8 wording) | **Decided 2026-11-13: (a)** — the whole point is that developers never overwrite each other's tracked file. Refines Q-5/Q-8: the root is always `aldc-external:/`; in `none` it shows the README only. |

### Access rule (decided, Q-3)

1. `#bcquality` (`read` / `list`) — whenever the tool is available in the session.
2. If the tool is missing or fails: read through the mount the session can reach —
   a. the virtual URI `aldc-external:/bcquality/<path>` (Local harness file tools; one or three slashes after the scheme, never two — measured with the spike scheme),
   b. the resolved clone path from `#aldcConfiguration` → `resolvedHome` (absolute path, where file tools may read it),
   c. `.external/bcquality/<path>` (junction mode).
3. Never block: if nothing is reachable, apply `external.bcquality.fallback` (skills-mode) and record the reason.

## Migration (G-4)

Run by the extension's startup reconcile when `autoReconcile = true`, per repository. The workspace entry is the
same in every mode (Q-9), so the table below is superseded by spec §6: the workspace is migrated once to the
constant entry — from the `.external` path root **and** from the legacy layout that mounted the clone directly
(pre-D-49, a different path per developer; today handled by `Migrate-AprodaProjectLayout.ps1`) — and the mount only
decides about the junction. Kept for the history of Q-5/Q-8:

| Current state | Mount `virtual` | Mount `junction` | Mount `none` |
|---|---|---|---|
| workspace has `.external` root, junction present | workspace: `.external` root → virtual root (JSONC edit that keeps comments); junction: remove the link only (on a share removal may fail → warning with `cmd /c rmdir`) | unchanged | root stays a path root; junction: remove the link only |
| workspace has `.external` root, no junction | workspace edit as above | create the junction (today's behaviour) | nothing |
| workspace has the virtual root | nothing | workspace: virtual root → `.external` root, create the junction | workspace: virtual root → `.external` path root |

Writers that know the layout (F-14 lesson: change all of them): `tools/aproda-sync/templates/workspace.seed.jsonc`,
`Initialize-AprodaProject.ps1` (fallback workspace writer), `Migrate-AprodaProjectLayout.ps1`, the extension
reconcile. The tracked workspace file is in `neverTouch` for the syncer — only the extension edits it, and only
the `.external` root entry.

The spike used the scheme `aldc-bcq:` with the clone as root; the measured properties (read, containment,
no search leak, repoint, explicit error) carry over to `aldc-external:` with a source level in between.

## Deliverables (sketch — detailed in the spec)

| Area | Items |
|---|---|
| Extension | `FileSystemProvider` (read-only, resolver-backed, containment, `Unavailable` error naming the tried candidates); setting(s) per Q-1; reconcile + migration per mount; command *Aproda ALDC: Reveal BCQuality Clone*; A12 warning; *Show BCQuality Status* shows mount + reach; doctor checks; tests |
| Layer | seed template, `Initialize-AprodaProject.ps1`, `Migrate-AprodaProjectLayout.ps1`, `templates/external-readme.seed.md`, `docs/bcquality.md`, `aldc.yaml` comment (Q-7), access-rule prose in `copilot-instructions.md` + `al-conductor`, `al-review-subagent`, `al-triage`, `dredd` |
| Records | D-49 revision (new decision or addendum, D-16), D-7/D-2 register rows, `inPlaceEdits` if new upstream files are touched |

## Measurements still needed

| # | What | Where |
|---|---|---|
| M-1 | Is `aldc-external:/` reachable in a **Copilot-harness** session (run01 was a CLI/SDK session with path-based tools)? Decides how much step 2a of the access rule is worth. | Gustav, after the provider exists |
| M-2 | Migration on a real project on `I:` (junction present but broken) and on a `C:` project | Gustav + one local project |
| M-3 | AL language server and Problems with the virtual root (run02 showed no leak with the spike; repeat with the real provider) | Gustav |

## Phases

| Phase | Content | Gate |
|---|---|---|
| 0 | Decide Q-1…Q-8 | Florian — **done 2026-11-13** |
| 1 | Decision record (D-54, D-16), spec + test plan | review — **done 2026-11-13** |
| 2 | Extension: provider, settings, command, reconcile/migration, tests, VSIX | `npm test`, review — **done** (`0.3.0`) |
| 3 | Layer: templates, scripts, docs, agent/instruction prose | `aldc-validate`, review — **done** |
| 4 | Live test brief (M-1…M-3) in Gustav | evidence — **run 1 done** ([evidence](evidence/E011Evidence-run1.md)); defects D-1…D-5 fixed in `0.3.1`; retest open (L-11.1, L-11.2, L-11.8, L-11.11, step 0.3 README) |
| 5 | Release: extension, then layer | rollout per E-008 channels |
