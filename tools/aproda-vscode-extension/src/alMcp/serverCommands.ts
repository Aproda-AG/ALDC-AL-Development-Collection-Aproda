import * as vscode from "vscode";
import { Logger } from "../log";

// Single source of the label: the provider uses it as the definition label, the start id is derived from it.
export const serverLabel = "al-mcp";

// Measured in VS Code 1.144 (Q-23): the id is toKey(extension id) = lower-case extension id, "/", definition label.
export function ownServerIdFor(extensionId: string): string {
    return `${extensionId.toLowerCase()}/${serverLabel}`;
}

// The id comes only from the extension context, never from the model or user input.
let ownServerId: string | undefined;

export function configureOwnServer(extensionId: string): void {
    ownServerId = ownServerIdFor(extensionId);
}

export function currentOwnServerId(): string | undefined {
    return ownServerId;
}

export type StartResult = "started" | "failed";
export type RestartResult = "restarted" | "failed";

async function issue(command: "workbench.mcp.startServer" | "workbench.mcp.restartServer", logger: Logger): Promise<boolean> {
    if (!ownServerId) {
        logger.error(`${command} not issued: the own server id is not configured.`);
        return false;
    }
    logger.info(`${command} issued for '${ownServerId}'.`);
    try {
        await vscode.commands.executeCommand(command, ownServerId);
        return true;
    } catch (error) {
        logger.error(`${command} failed for '${ownServerId}': ${error instanceof Error ? error.message : String(error)}`);
        return false;
    }
}

// The command resolves without telling whether a server with that id exists, so "started" means "the command was issued".
export async function startOwnServer(logger: Logger): Promise<StartResult> {
    return await issue("workbench.mcp.startServer", logger) ? "started" : "failed";
}

export async function restartOwnServer(logger: Logger): Promise<RestartResult> {
    return await issue("workbench.mcp.restartServer", logger) ? "restarted" : "failed";
}
