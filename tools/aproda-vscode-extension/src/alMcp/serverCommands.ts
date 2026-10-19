import * as vscode from "vscode";
import { Logger } from "../log";

// TODO(Q-23): the argument VS Code expects for `workbench.mcp.startServer` / `workbench.mcp.restartServer` for a
// provider-registered server is not measured yet (E-010 spec §4.9). This is a GUESS (provider id + "/" + label).
// Measure with a scratch command, record the accepted form in E-010-plan.md, then change ONLY this constant and
// flip `ownStartPathConfirmed`. The server id must never come from the model or from user input.
export const ownServerIdCandidate = "aprodaAldc.alMcp/al-mcp";

// Doctor input (spec §4.8): false while Q-23 is open, so `auto` + `chat.mcp.autostart = never` is reported.
export const ownStartPathConfirmed = false;

export type StartResult = "started" | "failed";
export type RestartResult = "restarted" | "failed";

// workbench.mcp.startServer resolves without telling whether a server with that id exists, so "started" means
// "the command was issued", not "the server is running".
export async function startOwnServer(logger: Logger): Promise<StartResult> {
    try {
        await vscode.commands.executeCommand("workbench.mcp.startServer", ownServerIdCandidate);
        return "started";
    } catch (error) {
        logger.error(`workbench.mcp.startServer failed for '${ownServerIdCandidate}' (Q-23): ${error instanceof Error ? error.message : String(error)}`);
        return "failed";
    }
}

export async function restartOwnServer(logger: Logger): Promise<RestartResult> {
    try {
        await vscode.commands.executeCommand("workbench.mcp.restartServer", ownServerIdCandidate);
        return "restarted";
    } catch (error) {
        logger.error(`workbench.mcp.restartServer failed for '${ownServerIdCandidate}' (Q-23): ${error instanceof Error ? error.message : String(error)}`);
        return "failed";
    }
}
