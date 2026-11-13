# `.external/` — external knowledge, mounted but not compiled

This folder is the anchor of a **wrapper workspace root**. External knowledge bases (currently:
BCQuality) are mounted into VS Code through it without polluting project-wide search — a plain VS Code
workspace root cannot exclude *itself*, only its subfolders, so the knowledge base is never mounted
directly.

## The default: a virtual root

By default the `.external` workspace root is the constant virtual root
`{ "name": ".external", "uri": "aldc-external:/" }`, served by the Aproda ALDC extension. It shows the
BCQuality clone as `bcquality/` in the Explorer — read-only, nothing is created on disk, and it is the
same entry in every project. The real clone stays wherever it lives on your workstation.

## Mount modes

Set `aprodaAldc.external.mount` (user setting):

| Mode | Effect |
| --- | --- |
| `virtual` (default) | The `aldc-external:/` root serves the clone. No link on disk. |
| `junction` | The extension also maintains the link `.external/bcquality` (see *Junction mode*). |
| `none` | No mount at all. BCQuality stays reachable through the resolved clone path. |

## How agents reach BCQuality

Use the `#bcquality` tool when it is available. Otherwise read through what the session can reach:
`aldc-external:/bcquality/<path>`, the resolved clone path (`#aldcConfiguration` → `resolvedHome`), or
`.external/bcquality/<path>` in junction mode. Never block: with nothing reachable, the `fallback` policy
in `aldc.yaml` applies.

## Choosing the clone

The clone location is a property of **your workstation**, not of this repository. To point at a
*different* clone, set `aprodaAldc.bcquality.path`; it is the highest-precedence source the resolver
consults.

## Switching it off

| Switch | Scope | Effect |
| --- | --- | --- |
| `external.bcquality.enabled: false` in `aldc.yaml` | project, versioned | BCQuality is off for the project; a junction, if any, is **removed**. |
| `aprodaAldc.bcquality.autoReconcile: false` | user, machine-local | Nothing additive happens automatically: no mount or link is maintained. |

## Junction mode (optional)

> ⚠️ **In junction mode `bcquality/` is a link, not a folder. Never delete it recursively.** A recursive
> delete follows the link and erases the real BCQuality clone outside this repository.

`.external/bcquality` is then a **directory junction** (Windows) or **symlink** (macOS, Linux) pointing
at your clone. The extension creates it for you; by hand (no elevation needed on Windows):

```powershell
New-Item -ItemType Junction -Path .external\bcquality -Target <path-to-your-clone>
```

```bash
ln -s <path-to-your-clone> .external/bcquality
```

Delete the **link only**, never its contents:

```powershell
(Get-Item .external\bcquality -Force).Delete()
```

or

```powershell
cmd /c rmdir .external\bcquality
```

**Never run `Remove-Item -Recurse` (or any recursive delete) on this path** — it deletes *through* the
link and erases the real clone.

The workspace settings apply `search.exclude` and `files.watcherExclude` to `bcquality/**` (junction
mode only), so its ~200+ example `.al` files never show up in project-wide search. This deliberately
does **not** use `files.exclude` — that would block reading by explicit path, which agents (`dredd`,
`al-review-subagent`) rely on.

## Learn more

The full picture — resolution order, mount modes, what happens when BCQuality is not installed, how
agents consume it — lives in `docs/bcquality.md` (fork layout) / `.github/docs/bcquality.md` (project
layout); a single relative link cannot resolve on both sides, hence the prose pointer here.
