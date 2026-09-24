# How-To — Set up the Azure DevOps MCP Server (easy global setup)

> Not implemented yet — this is a reference for whoever picks up the MCP addition from
> [mcp-vs-cli.md](mcp-vs-cli.md). Sourced from official MS Learn docs (`azure/devops/mcp-server/*`,
> 2026-09-24).

## Use the remote server, not a local one

Microsoft hosts and maintains a **remote** Azure DevOps MCP Server — no Node.js, no `npx`, no local
process, no files to vendor into any repo:

- Endpoint: `https://mcp.dev.azure.com/{organization}` → for Aproda: `https://mcp.dev.azure.com/alphasol`
- Transport: streamable HTTP
- Auth: Microsoft Entra ID (OAuth) — same tenant already used for `az login --tenant 8ad57af3-4ca5-4c66-bc7d-a52dd71dc7c9`
- Prerequisite: the ADO organization must be backed by a Microsoft Entra tenant (Aproda's `alphasol` org
  already is, per the existing `az login` setup)

MS guidance, verbatim: *"Use the remote MCP Server when your environment supports it. The remote server
is the recommended option because it requires no local installation and Azure DevOps manages its
updates."*

> **Do not vendor a local server into a repo.** Even the local option (for clients that can't do Entra
> OAuth, e.g. Claude Desktop/Codex) is meant to run via `npx -y @azure-devops/mcp {org}` — `npx` caches
> the package in the global npm cache, not in the project folder. A checked-in `node_modules` folder
> (as found in `azure-devops-administration/.github/mcp/`) is not how Microsoft ships this and is the
> direct cause of the "extremely many files per repo" problem.

## Supported clients for the remote server

✅ VS Code + GitHub Copilot, Visual Studio, Microsoft Foundry, Microsoft Copilot Studio, GitHub Copilot
CLI, GitHub Copilot app.
⚠️ Cursor / Claude Code — need a custom Microsoft Entra app registration first.
❌ Claude Desktop, Codex — Entra dynamic client registration not supported; must use the local server.

Aproda's stack (VS Code + GitHub Copilot) is fully supported out of the box.

## Setup — global, once per workstation (not per repo)

1. Open the Command Palette (`Ctrl+Shift+P`).
2. Run **`MCP: Open User Configuration`** (alternative: **`MCP: Add Server`** → transport **HTTP** →
   destination **Global**). This writes to your VS Code **user profile**, not to any repo's
   `.vscode/mcp.json` — the server becomes available in every workspace afterward.
3. Add:

   ```json
   {
     "servers": {
       "ado": {
         "type": "http",
         "url": "https://mcp.dev.azure.com/alphasol"
       }
     }
   }
   ```

4. Open GitHub Copilot Chat, switch to **Agent Mode**. On first use you'll be prompted to sign in with
   your Microsoft Entra account (same one used for `az login`).
5. Open the tools picker (wrench icon) and confirm the `ado` server's tools are listed.

No `.vscode/mcp.json` in any project repo, no `package.json`, no `node_modules` — one config, one time,
covers every ALDC/Aproda repo on that workstation.

## Scoping (recommended before enabling writes)

Two headers narrow what the connection can do — add them under the server entry:

```json
{
  "servers": {
    "ado": {
      "type": "http",
      "url": "https://mcp.dev.azure.com/alphasol",
      "headers": {
        "X-MCP-Toolsets": "repos",
        "X-MCP-Readonly": "true"
      }
    }
  }
}
```

- `X-MCP-Toolsets` — comma-separated category scoping (`repos`, `wit`, `pipelines`, `wiki`, `work`,
  `testplan`, `elm`; default `all`). Per [mcp-vs-cli.md](mcp-vs-cli.md)'s recommendation, start with
  `repos` only — that's the toolset containing the PR-thread-comment gap this is meant to close.
- `X-MCP-Readonly` — global read-only switch for the whole connection. Turn this **off** only once the
  preview-and-approve wrapper around the write-classified PR tools exists (see mcp-vs-cli.md) — until
  then, keep it `true` so the connection can be explored/tested without any write risk.

> These two headers are **connection-level**, not per-call — they cannot replicate the parameter-level
> carve-outs (e.g. blocking only `--bypass-policy true`) the `az`-CLI scripts have. Don't rely on them as
> a substitute for the HITL wrapper that still needs to be built around the write tools.

## Verify the connection

Ask Copilot Chat (in Agent Mode):

- "List the projects in my Azure DevOps organization."
- "Show my assigned work items."
- "What pull requests need my review?"

Correct results confirm the server is reachable and authenticated.

## Troubleshooting quick reference

| Symptom | Fix |
|---|---|
| Copilot doesn't use MCP tools at all | Confirm Agent Mode is active — MCP tools aren't available in normal chat mode. Be explicit in the prompt (e.g. "Use Azure DevOps to get my current sprint work items"). |
| "Connection Refused" | Confirm outbound HTTPS to `mcp.dev.azure.com` is allowed (corporate proxy/firewall); retry without VPN to isolate network path issues. |
| Auth/sign-in fails | `Ctrl+Shift+P` → **Accounts: Sign Out**, then reconnect; if that doesn't help, **Developer: Reload Window**. |
| Conditional Access blocks sign-in | Same Conditional Access policies that apply to ADO web/CLI access apply here too (location/device-based restrictions) — check from a compliant device/network. |
| Stale/cached data returned | Add "Don't use previously fetched data" to the prompt to force a fresh query. |

## References

- [Enable AI assistance with Azure DevOps MCP Server](https://learn.microsoft.com/en-us/azure/devops/mcp-server/mcp-server-overview)
- [Set up the remote Azure DevOps MCP Server](https://learn.microsoft.com/en-us/azure/devops/mcp-server/remote-mcp-server)
- [Troubleshoot the remote Azure DevOps MCP Server](https://learn.microsoft.com/en-us/azure/devops/mcp-server/remote-mcp-server-troubleshooting)
