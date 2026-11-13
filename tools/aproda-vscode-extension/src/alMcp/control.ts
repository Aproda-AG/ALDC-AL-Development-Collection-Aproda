import { Logger } from "../log";
import { alMcpStartMode } from "../config";
import { isAlWorkspace } from "../workspace/alWorkspace";
import { restartOwnServer, startOwnServer } from "./serverCommands";

export interface StartRequestTarget {
    isStartRequested(): boolean;
    requestStart(): void;
    waitForDefinitionFetched?(timeoutMs: number): Promise<boolean>;
}

// Mutable so tests can shrink the waits.
export const startDelays = { fetchTimeoutMs: 5000, settleMs: 300 };

export type ControlState = "started" | "restarted" | "failed" | "notAlWorkspace";

export interface ControlResult {
    readonly state: ControlState;
    readonly server: "al-mcp";
    readonly message: string;
}

const failureHint = "VS Code did not accept the start command (see the Aproda ALDC log). Start the server from MCP: List Servers.";

// Shared by the commands and the chat tool. The server id never comes from the caller (serverCommands derives it).
export async function controlAlMcp(action: "start" | "restart", provider: StartRequestTarget, logger: Logger): Promise<ControlResult> {
    if (!isAlWorkspace()) {
        return { state: "notAlWorkspace", server: "al-mcp", message: "The open workspace is not an AL workspace (no folder with app.json); the AL MCP server is not provided." };
    }
    const manual = alMcpStartMode() === "manual";
    // In manual mode a restart of a server that was never provided would do nothing, so it becomes a start.
    if (action === "start" || (manual && !provider.isStartRequested())) {
        if (manual) {
            await requestManualStart(provider, logger);
        }
        return await startOwnServer(logger) === "started"
            ? { state: "started", server: "al-mcp", message: "Start requested for the AL MCP server. The first start of this server shows VS Code's MCP trust dialog." }
            : { state: "failed", server: "al-mcp", message: failureHint };
    }
    return await restartOwnServer(logger) === "restarted"
        ? { state: "restarted", server: "al-mcp", message: "Restart requested for the AL MCP server." }
        : { state: "failed", server: "al-mcp", message: failureHint };
}

// VS Code registers the server only after it fetched the definition; an earlier startServer is a silent no-op.
async function requestManualStart(provider: StartRequestTarget, logger: Logger): Promise<void> {
    if (provider.isStartRequested() || !provider.waitForDefinitionFetched) {
        provider.requestStart();
        return;
    }
    const fetched = provider.waitForDefinitionFetched(startDelays.fetchTimeoutMs);
    provider.requestStart();
    if (await fetched) {
        await new Promise((resolve) => setTimeout(resolve, startDelays.settleMs));
    } else {
        logger.warn(`AL MCP definition was not fetched by VS Code within ${startDelays.fetchTimeoutMs} ms; issuing the start command anyway.`);
    }
}
