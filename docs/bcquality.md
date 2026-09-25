# BCQuality — external citable knowledge for reviews & audits

BCQuality is an **optional** layer that gives ALDC's review/audit agents a curated,
**citable** Business Central knowledge base. When it is mounted, `al-review-subagent`,
`@dredd`, and `@al-triage` back their findings with a real knowledge file; when it is
**absent (the default)**, they fall back to the native A–G checklist + auto-applied
instructions and **never block**. You only need this if you want BCQuality-cited
reviews.

## How the integration works

- **Consumed externally — not a submodule.** ALDC clones BCQuality **outside**
  every repository, at `<developer root>/BCQuality-Aproda` by default. Because
  that clone has no `app.json`, the AL compiler never builds it, so its example
  `.al` files can't pollute your extension's error list.
- **Reached through a tracked wrapper, `.external/`, never mounted directly.**
  A directly-mounted clone is itself a workspace root, and **a workspace root
  cannot exclude itself** from search (`search.exclude` globs are evaluated
  relative to each mounted root) — so the clone's 246 example `.al` files used
  to leak into every symbol search and Quick Open (E-006 finding **B-9**). The
  fix: `.external/` is the mounted root, and `bcquality/` is a **directory
  junction** (Windows) / symlink (macOS, Linux) **one level inside it** —
  `.external/bcquality`. Because the junction is now a genuine subfolder of the
  mounted root, `search.exclude` + `files.watcherExclude` on `bcquality/**`
  finally resolve, and the clone disappears from search while staying fully
  readable by path. **Never `files.exclude`** — that would hide the folder
  outright and break the read path the agents depend on. `.external/README.md`
  is tracked and ships with every project; it explains the junction and the
  manual creation/removal commands if the extension is unavailable.
- **The source is configurable; the default is the canonical upstream.** Out of the
  box `aldc.yaml → external.bcquality.url` points at **[`microsoft/BCQuality`](https://github.com/microsoft/BCQuality)**
  (the source of truth for the upstream install scripts). Point `url` at **your
  own fork** if you maintain one. By default it tracks the `ref` branch
  (`main`); set `pinnedCommit` to a 40-hex SHA for reproducible runs — **note
  that today only `tools/bcquality/install.sh`/`install.ps1` honour `url` /
  `ref` / `pinnedCommit`; the Aproda VS Code extension's install command does
  not yet (E-006 T-34, deferred)**.
- **ALDC "hooks in" by calling the meta-skill `entry.md`.** The agents do **not**
  hardcode which BCQuality skills to run. They read the entry point
  (`<home>/skills/entry.md`, per `aldc.yaml`) and **execute whatever its `dispatch[]`
  returns** — Entry owns the routing. As BCQuality's coverage grows, ALDC picks it up
  with no change on this side.
- **Configuration lives in `aldc.yaml → external.bcquality`**: `enabled`
  (`auto` | `true` | `false`), `url`, `ref`, optional `pinnedCommit`, `home` (a
  static fallback, see below), `entryPoint` (`skills/entry.md`), the multi-root
  `workspace`, and the absent-path `fallback` policy.
- **The real clone location is resolved by the extension, not read off one
  config line.** `aldc.yaml → external.bcquality.home` is only a static
  default / last-resort fallback. The Aproda VS Code extension's resolver
  (`src/bcquality/resolve.ts`) is the authority: on every call it probes, in
  order, (1) the user setting `aprodaAldc.bcquality.path`, (2) every mounted
  workspace folder and its `bcquality` subfolder, (3) the `$BCQUALITY_HOME`
  environment variable, (4) `<developer root>/BCQuality-Aproda`, and only then
  (5) `aldc.yaml → external.bcquality.home`. Each candidate is accepted only
  after **probing** `<candidate>/skills/entry.md` — nothing is trusted
  unverified, and nothing is cached, so a stale answer cannot survive a moved
  or reinstalled clone.
- **The `enabled` switch is resolved ONCE by `al-conductor`** and propagated to the
  subagents (recorded in the plan doc): `auto` probes to detect, `true` expects it
  (probe + warn if absent), `false` disables it entirely (native A–G, **no probe**).
  Subagents consume that decision and do not re-probe — except `@dredd`/`@al-triage`
  run standalone, so they read `enabled` and probe themselves.

## Reaching BCQuality from the editor

- **`#bcquality` language-model tool** — the agent channel. Serves `read` and
  `list` against the resolved clone root, the same way `#aldcConfiguration`
  serves `aldc.yaml`. Agent prose keeps a direct path read as a documented
  fallback for when the tool is unavailable (dual path).
- **Status-bar item + `Aproda ALDC: Show BCQuality Status` command** — the
  human-facing view of the same resolver. It lists every candidate in
  precedence order with its verdict (verified / no entry point / missing /
  not set), shows the resolved root next to the *declared*
  `aldc.yaml → external.bcquality.home` value side by side (rather than ever
  writing one into the other), and shows whether the `.external/bcquality`
  junction currently exists.

## Install (only if you want BCQuality-backed reviews)

The Aproda-sanctioned route is the **VS Code extension**, not the shell/PowerShell
scripts below:

1. Run **`Aproda ALDC: Install / Update BCQuality`** (also offered from
   `Show BCQuality Status` when nothing resolves). It clones/updates the
   configured repository into `<developer root>/BCQuality-Aproda`.
2. If `aprodaAldc.bcquality.autoReconcile` is enabled (default: on), the
   extension also maintains the Global `BCQUALITY_HOME` setting and creates
   the `.external/bcquality` junction for you automatically once a clone is
   verified.
3. **`autoReconcile` is deliberately asymmetric.** Turning it off only stops
   the *additive* work — updating the Global setting and creating the
   junction. It does **not** stop *removal*: if BCQuality is disabled in
   `aldc.yaml` (`external.bcquality.enabled: false`), an existing junction is
   removed regardless of this setting, because a kill-switch must never leave
   a live BCQuality mount behind.
4. Without the extension, create the junction by hand per
   `.external/README.md`: `New-Item -ItemType Junction -Path .external\bcquality -Target <clone>`
   (Windows, no elevation) / `ln -s <clone> .external/bcquality` (macOS, Linux).
5. The upstream scripts `tools/bcquality/install.sh` / `install.ps1` still
   exist and read `url` / `ref` / `pinnedCommit` from `aldc.yaml`, but are not
   the path the extension uses (E-006 B-11) — they remain useful mainly for
   scripted / headless setups.

**Then use it.** Run a review/audit as usual:

- `@al-conductor` review phases, `@dredd` (independent audit), `@al-triage`
  (diagnosis) each probe BCQuality (via `#bcquality` or the direct-read
  fallback), read `entry.md`, and fold cited findings into their output.
- If the probe fails (not installed / disabled), they record BCQuality as
  `not-applicable`, review against the full **A–G** native checklist, and carry
  on — nothing blocks.

## Removing a junction — link only, never recursive

`.external/bcquality` is a junction/symlink, not a real directory. Delete the
**link only** — e.g. `(Get-Item .external\bcquality -Force).Delete()` or
`cmd /c rmdir .external\bcquality` on Windows, `rm .external/bcquality` on
macOS/Linux. **Never `Remove-Item -Recurse` / `rm -rf`** on it: a recursive
delete follows the link and destroys the real clone at its target, not just
the pointer.

## Pin & evidence

`aldc.yaml → external.bcquality` declares `url`, `ref` and the optional
`pinnedCommit`; the upstream install scripts read it from there. Pinning is
**optional**: set `pinnedCommit` to a 40-hex SHA for reproducible runs, or
leave it empty to track the `ref` branch. `tools/bcquality/validate_evidence.py`
checks that every citation in a persisted review/audit report resolves to a
real file **inside** the clone — a hallucinated citation fails the build.

**This validator and its CI workflow (`bcquality-evidence.yaml`) are fork/CI-only
today.** Neither file ships to a consuming project (E-006 findings **B-3**/
**B-4**) — so in a consuming project the evidence chain is declarative, not
enforced. `T-21`/`T-23` (deferred to Block 5) track whether/how that changes.

To change the source or version, edit `url` / `ref` / `pinnedCommit` in `aldc.yaml`.

## Notes

- **Absent is the default.** A fresh ALDC install does not clone BCQuality; you opt
  in via `Aproda ALDC: Install / Update BCQuality` (or the upstream scripts).
- BCQuality is a **citation/audit layer** — it does not replace the auto-applied
  `*.instructions.md` or the domain skills; it adds evidence-backed findings on top.
