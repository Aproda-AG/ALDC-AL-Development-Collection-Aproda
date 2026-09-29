# Reference: Missing-Dependency Resolution (FKH)

> Loaded on demand by [`../SKILL.md`](../SKILL.md) → *Publish a Dependency-Ordered App Set*.

## When this applies

`sortapps.ps1` reports `UnknownDependencies`, or `fkh getappinfo` shows a dependency of a published app that is not `IsInstalled`/`IsPublished` on the target container. In both cases, the local `.installapps` set is incomplete — an app the target needs is not among the files being published.

## Resolution is HITL — never automatic

Finding a plausible dependency file is **not** authorization to publish it. Match the missing dependency (name, publisher, version) against the known Aproda app sources below, then **stop and offer the match to the user** — name the file and its path, and wait for explicit confirmation before adding it to the publish set. Do not copy, publish, or install a dependency the user has not confirmed, even when exactly one candidate matches.

If no candidate is found under any of the known sources, stop and ask the user directly; do not guess a substitute version or search elsewhere.

## Known Aproda app sources

See [`../../../.github/site-profile.aproda.md`](../../../.github/site-profile.aproda.md) → *Aproda App Sources* for the canonical, site-wide fileshare locations (ASFL foundation layer, other Aproda modules, third-party/Fremd Module) and the `Archiv Signed` convention for older versions.

## Correct install order

Resolve and publish in **tiers**, foundation-most first; apps within the same tier still go through the existing local dependency sort (`sortapps.ps1`):

1. **ASFL** (Aproda Foundation Layer) — the base every other Aproda AppSource app depends on.
2. **Other Aproda modules** (public Cloud).
3. **Third-party / Fremd Module** apps.
4. **Project apps** (the `.installapps` set being deployed).

Publish tier-by-tier, stopping at the first error, exactly like the existing dependency-ordered publish loop in `../SKILL.md`.
