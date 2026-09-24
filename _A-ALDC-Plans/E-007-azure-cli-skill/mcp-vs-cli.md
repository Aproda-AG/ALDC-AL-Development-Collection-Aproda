# MCP vs. CLI — Comparison & Decision Notes

> Captures the design discussion from the E-007 conversation (2026-09-24): should `skill-aproda-ado`
> stay `az`-CLI-based, move to the Azure DevOps MCP Server, or combine both? Nothing here is
> implemented — this is the reasoning trail behind the recommendation at the end.

## Why this came up

While designing the 4-tier write model (Phase 2 of the plan), one gap surfaced: **there is no
`az repos pr comment` command at all** — confirmed via MS Learn ("Review pull requests" doc: *"You can
only review Azure DevOps PRs in the web portal by using your browser"*). The only CLI-reachable review
action is `az repos pr set-vote` (Approve/Reject/Wait-for-author/Reset). The official **Azure DevOps MCP
Server**, by contrast, ships a dedicated tool for exactly this gap — which raised the question: should we
just use MCP instead of (or alongside) the `az`-CLI scripts?

## What the ADO MCP Server actually offers (relevant excerpt)

| Tool | Action | Read-only |
|---|---|---|
| `repo_pull_request_thread_write` | `create` — new comment thread on a PR | ❌ |
| `repo_pull_request_thread_write` | `reply` — reply to a thread | ❌ |
| `repo_pull_request_thread_write` | `update_status` — resolve/close a thread | ❌ |
| `repo_pull_request_write` | `vote` — Approve/Reject/etc. | ❌ |
| `repo_pull_request_write` | `update_reviewers` — add/remove reviewers | ❌ |
| `repo_pull_request_write` | `update` — update a PR, **including setting auto-complete** | ❌ |
| `wit_work_item_write` / `wit_work_item_comment_write` | create/update work items and comments | ❌ |
| `repo_pull_request`, `repo_pull_request_thread`, `wit_work_item`, `wit_query`, … | assorted reads | ✅ |

Backed by the ADO REST API directly (Pull Request Threads endpoint etc.), not by `az`. Auth is Microsoft
Entra ID (OAuth) for the remote server — same tenant Aproda already uses for `az login`.

## Side-by-side

| | Current: 4 `az`-CLI scripts | Azure DevOps MCP Server |
|---|---|---|
| **PR comments/threads** | ❌ not possible — no such `az` command exists | ✅ native (`repo_pull_request_thread_write`) |
| **PR votes / reviewers** | ✅ both exist (`az repos pr set-vote`, `az repos pr reviewer add`) | ✅ native |
| **Capability breadth** | Narrow, exactly what we wrote | Broad — work items, pipelines, wiki, test plans, search, ELM, and more |
| **Maintenance** | We own every script; org-URL bug (F-1) and error-swallowing (F-2/F-3) were our own bugs to find | Microsoft-maintained, updated with the ADO API |
| **Granularity of gating** | Per-script, per-parameter (we can block exactly `--bypass-policy true` and nothing else in `pr update`) | Per-**connection**, not per-call — `X-MCP-Readonly` and `X-MCP-Toolsets` are coarse (category-level: `repos`, `wit`, `pipelines`, …), not per-action |
| **HITL preview-and-approve gate** | Built into the scripts (`ShouldProcess`, mandatory AI-disclaimer append, explicit chat approval before every write) | **None built in** — an MCP tool is just a callable function; the same gate would have to be rebuilt around MCP tool calls instead of `az` calls |
| **Attack surface (untrusted ADO text → prompt injection)** | Deliberately minimized — `SKILL.md` states "no general REST/API access" as a constraint | Structurally closer to "general API access"; broader tool catalog = broader blast radius if an agent is ever tricked by hostile ADO content |
| **New moving parts** | None — reuses the `az login` session already required for other tooling | A new server connection (remote: `mcp.dev.azure.com`; local: Node.js process) that must be configured once per workstation |
| **Org already Entra-backed?** | N/A (uses `az login --tenant …` today) | Yes — required for the remote server, and Aproda's tenant already satisfies this |

## Where MCP genuinely wins

- Closes the one real capability gap (PR thread comments) that `az` CLI cannot close at all, structurally.
- Removes an entire category of "did we implement this az flag correctly" bugs (org-URL format, argument
  escaping, `az.cmd`/`cmd.exe` re-parsing) because we'd stop hand-rolling `az` invocations for whatever we
  route through MCP.

## Where MCP does **not** solve our actual problem

The core of E-007 Phase 2 (the 4-tier model: hard-forbidden / trusted-optional / HITL-gated / read) is a
**governance** problem, not a **capability** problem. Switching backend from `az` to MCP:

- Does **not** give us finer-than-connection-level scoping for free — `X-MCP-Readonly` is all-or-nothing
  per connection, `X-MCP-Toolsets` is category-level (e.g. all of `repos`), not "this one write action."
  Our Tier-1 carve-outs (block only `--bypass-policy true` inside an otherwise-allowed `pr update`) have
  no MCP equivalent — the MCP tool would need to expose the same fine-grained blocking itself, and it
  doesn't.
- Does **not** ship the preview-and-explicit-approval gate, nor the mandatory-AI-disclaimer enforcement,
  nor the read-first-then-show-then-confirm pattern our scripts implement today. That logic would have to
  be rebuilt in the agent/skill layer around MCP tool calls — same amount of design and instruction work,
  different backend.
- **Increases** the surface exposed to untrusted ADO text (SKILL.md's own stated constraint is "no general
  REST/API access") unless toolsets are scoped tightly and read-only is used wherever possible.
- Adds a new configured dependency (even the "easy" remote-server path is a new connection a dev must
  register once) versus reusing the already-required `az` CLI session.

## Recommendation

**Hybrid, not replacement.**

1. Keep the 4 `az`-CLI scripts for what they already do (work item read/comment/state, PR create) — they
   are narrow, auditable, and already carry the HITL gate we designed.
2. Add the Azure DevOps MCP Server **only** to close the PR-thread-comment gap, scoped to the minimum
   needed:
   - Remote server (see [howto-setup-ado-mcp.md](howto-setup-ado-mcp.md)), registered once at VS Code
     user level.
   - `X-MCP-Toolsets: repos` (nothing else) to keep the tool catalog as narrow as the gap being closed.
   - Wrap the write-classified MCP tools (`repo_pull_request_thread_write`, `repo_pull_request_write`)
     in the **same** preview-and-explicit-approval pattern already used for `Create-AdoPullRequest.ps1` /
     `Update-AdoWorkItem.ps1` — this is new instruction/skill work regardless of backend, not something
     MCP gives us automatically.
3. Do **not** use MCP as a blanket replacement for the tiered `az`-CLI model designed in Phase 2 — the
   governance gap (Tier 1 hard-forbidden, parameter-level carve-outs like `--bypass-policy`) still needs
   to be solved explicitly, on whichever backend ends up calling the write.

This keeps the existing D-16/D-48 sign-off scope limited to the tier model itself; adding MCP for the
comment gap is an **additive** skill capability (new tool available) rather than a policy relaxation, but
still needs the same explicit-approval wrapper before any write-classified MCP tool is actually callable
by an agent.
