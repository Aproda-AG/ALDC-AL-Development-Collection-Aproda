# E-007 — Azure CLI Skill (`skill-aproda-ado`) Hardening

> **Status (2026-09-24):** **Implemented and reviewed.** Design evolved from a pure-`az`-CLI tier model
> (V1) to an **MCP-first hybrid architecture (V2)** — see [E-007-V2.md](E-007-V2.md) for the target
> design. D-48 recorded in `decisions.aproda.md`; `skill-aproda-ado` rewritten (building blocks +
> tiered policy), the 4 old per-operation scripts retired, onboarding/walkthrough/readme updated. An
> independent review (Claude Opus 5) found 5 major issues, all fixed and re-verified — see
> [E-007-V2.md](E-007-V2.md) for the outcome.

## Why this exists

Some devs reported "Azure CLI works for ADO everywhere, except when Aproda ALDC uses it." A parallel
diagnosis (`azure-devops-administration/functions/ado-cli-access-diagnose`) had already ruled out a
permissions/Conditional-Access problem for the reporting dev (Konstantin Prell case, 3 clean test runs).
That left the ALDC-specific code path as the suspect.

## TL;DR

| # | Finding | Status |
|---|---------|--------|
| **F-1** | `az --organization` requires a fully qualified URL (`https://dev.azure.com/alphasol`). All 4 `skill-aproda-ado` scripts passed `$Organization` straight through to `az`, and every doc surface only ever documented the bare name (`Org = alphasol`) — never the required URL form. An agent following the docs would very plausibly pass the bare name, which `az` rejects. | ✅ **Fixed** — `-Organization` now defaults to the fixed `https://dev.azure.com/alphasol` in all 4 scripts; docs updated. |
| **F-2** | All 4 scripts swallow the real `az` error (`2>$null`) and surface only a generic "not reachable" message — this is why F-1 looked like a permissions problem instead of a parameter-format bug. | 🟧 Open — see Phase 1 |
| **F-3** | On validation-only failures (no `az` call happened yet), scripts don't set `$LASTEXITCODE`, leaving it at whatever a prior, unrelated command left behind — an agent checking the exit code can read a stale, wrong result. | 🟧 Open — see Phase 1 |
| **F-4** | `Title` (untrusted input, e.g. agent-composed PR title) is only partially sanitized (`"` only) before reaching `az.cmd`, which re-parses through `cmd.exe` on Windows — `&`, `\|`, `^`, `<`, `>` are not neutralized. | 🟧 Open — see Phase 1 |
| **F-5** | The skill's write surface is a rigid 2-command allowlist ("Forbidden: everything else"). Reworked into a 4-tier model (hard-forbidden / trusted / HITL-gated / read) per maintainer decision during design. | 🟨 Designed, not implemented — see Phase 2 |
| **F-6** | Preflight code (`Get-Command az`, extension check) is duplicated verbatim in all 4 scripts. | 🟧 Open — see Phase 3 (optional) |

## Reading order

| Document | Contents |
|----------|----------|
| [E-007-V2.md](E-007-V2.md) | **Current target design** — MCP-first hybrid architecture: Agent Instructions policy layer, shared disclaimer building block, az-CLI building blocks + `Invoke-AdoAzCli` wrapper, MCP connection scoping, tier-to-tool mapping for both backends, open questions |
| [E-007-plan.md](E-007-plan.md) | V1 (superseded by V2's architecture, but findings still relevant): error-handling hardening, the original CLI-only 4-tier write model, the preflight/auth-script consolidation idea |
| [mcp-vs-cli.md](mcp-vs-cli.md) | Why MCP was considered at all, what it does and doesn't solve — the reasoning that led to V2 |
| [howto-setup-ado-mcp.md](howto-setup-ado-mcp.md) | Reference for the recommended MCP setup: remote server, one-time global VS Code user-level config, toolset/read-only scoping headers, troubleshooting |

## Governance note (D-16)

`skill-aproda-ado/` matches `skill-aproda-*/**` → any edit here is an Aproda-layer edit. The tier-model
change (Phase 2) **relaxes** the original D-4 narrow-allowlist design, so it needs its own
`decisions.aproda.md` entry (proposed as **D-48** below) and explicit maintainer confirmation before
`SKILL.md`/the scripts are touched — the guardrail in `aproda-aldc-steward.aproda.instructions.md`
applies manually in this fork (its `applyTo` cannot fire here, see D-16 scope correction).
