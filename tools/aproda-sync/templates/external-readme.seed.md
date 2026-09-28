# `.external/` — external knowledge, mounted but not compiled

> ⚠️ **`bcquality/` is a link, not a folder. Never delete it recursively.** A recursive delete follows
> the link and erases the real BCQuality clone outside this repository. See *Removing it* below.

This folder is a **wrapper workspace root**. It exists so that external knowledge bases (currently:
BCQuality) can be mounted into VS Code without polluting project-wide search — a plain VS Code
workspace root cannot exclude *itself*, only its subfolders, so the knowledge base is never mounted
directly.

## What `bcquality/` is

`.external/bcquality` is not a directory — it is a **directory junction** (Windows) or **symlink**
(macOS, Linux) pointing at a BCQuality clone that lives **outside this repository**, somewhere else on
your workstation. If you see a yellow, non-expandable entry named `bcquality` in the Explorer, the link
has not been created yet (or its target moved); it does not mean the repository is broken.

## Why a junction instead of a normal subfolder

The clone location is a property of **your workstation**, not of this repository — everyone on the team
keeps their clone somewhere different. The junction keeps the repo-side path constant
(`.external/bcquality`, always) while the actual target varies per developer. Nothing in the repository
needs to know or care where your clone really is.

## Who creates it

The **Aproda VS Code extension** creates and maintains this junction automatically, as part of
*Apply Toolkit* / *Install-Update BCQuality*. In the normal workflow you never touch this folder
yourself.

## Creating it by hand (extension unavailable)

Windows (no elevation needed):

```powershell
New-Item -ItemType Junction -Path .external\bcquality -Target <path-to-your-clone>
```

macOS / Linux:

```bash
ln -s <path-to-your-clone> .external/bcquality
```

## Removing it — read this before you delete anything here

Delete the **link only**, never its contents:

```powershell
(Get-Item .external\bcquality -Force).Delete()
```

or

```powershell
cmd /c rmdir .external\bcquality
```

**Never run `Remove-Item -Recurse` (or any recursive delete) on this path.** A recursive delete follows
the link and deletes *through* it — it will erase the real BCQuality clone outside the repository, not
just the pointer to it.

### Deleting the link does not switch BCQuality off

The Aproda ALDC extension re-establishes the link whenever a window opens on an initialized project, so
a link you delete by hand is simply back next time. That is deliberate: an init that rewrites the
`*.code-workspace` makes VS Code reload the window, which kills the extension mid-run — without this,
the link would silently never be created on a first init.

There are two real off-switches, and they do different things:

| Switch | Scope | Effect |
| --- | --- | --- |
| `external.bcquality.enabled: false` in `aldc.yaml` | project, versioned | The link is **removed** and stays removed. Applies even when the setting below is off. |
| `aprodaAldc.bcquality.autoReconcile: false` | user, machine-local | Nothing additive happens: no link is created and `BCQUALITY_HOME` is not maintained. An existing link is left untouched. |

To point at a *different* clone, do not re-target the link by hand — it is replaced on the next window.
Set `aprodaAldc.bcquality.path` instead; it is the highest-precedence source the resolver consults.

## The exclude rule VS Code uses for this folder

The workspace settings apply `search.exclude` and `files.watcherExclude` to `bcquality/**`, so its
~200+ example `.al` files never show up in project-wide search or Quick Open. This deliberately does
**not** use `files.exclude` — that setting would hide the folder from the Explorer *and* block reading
it, and agents (`dredd`, `al-review-subagent`) rely on reading BCQuality content by explicit path.

## Learn more

The full picture — resolution order, what happens when BCQuality is not installed, how agents consume
it — lives in `docs/bcquality.md` (fork layout) / `.github/docs/bcquality.md` (project layout); a single
relative link cannot resolve on both sides, hence the prose pointer here.
