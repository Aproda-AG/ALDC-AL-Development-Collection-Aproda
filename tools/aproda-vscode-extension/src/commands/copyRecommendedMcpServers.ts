import * as vscode from "vscode";

// A fragment, not a whole-file document: many workstations already have other entries in their user
// mcp.json (e.g. al-symbols-mcp), so pasting a full top-level document risks overwriting them. This
// pastes directly inside an existing "servers": { ... } object instead.
const RECOMMENDED_MCP_SERVERS = `"microsoft-learn": {
    "type": "http",
    "url": "https://learn.microsoft.com/api/mcp"
},
"context7": {
    "type": "http",
    "url": "https://mcp.context7.com/mcp"
},
"ado": {
    "type": "http",
    "url": "https://mcp.dev.azure.com/alphasol",
    "headers": {
        "X-MCP-Toolsets": "repos,wit"
    }
}`;

export async function copyRecommendedMcpServers(): Promise<void> {
    await vscode.env.clipboard.writeText(RECOMMENDED_MCP_SERVERS);
    void vscode.window.showInformationMessage("Recommended MCP server entries copied to clipboard.");
}
