import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { alMcpStartMode } from "../config";
import { describeActiveAltool } from "./altool";
import { ownStartPathConfirmed } from "./serverCommands";

export interface AlMcpFinding {
    readonly level: "info" | "warning";
    readonly message: string;
}

// Duplicate registration: a workspace mcp.json (or the workspace file) that still starts altool itself next to the provider.
export function findDuplicateRegistrations(): string[] {
    const candidates: string[] = [];
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        candidates.push(path.join(folder.uri.fsPath, ".vscode", "mcp.json"));
    }
    const workspaceFile = vscode.workspace.workspaceFile;
    if (workspaceFile && workspaceFile.scheme === "file") {
        candidates.push(workspaceFile.fsPath);
    }
    return candidates.filter((candidate) => {
        try {
            return /launchmcpserver/i.test(fs.readFileSync(candidate, "utf8"));
        } catch {
            return false;
        }
    });
}

export function collectAlMcpFindings(): AlMcpFinding[] {
    const findings: AlMcpFinding[] = [];
    const mode = alMcpStartMode();
    findings.push({ level: "info", message: `AL MCP start mode: ${mode}` });

    const altool = describeActiveAltool();
    if (altool.state === "found") {
        findings.push({ level: "info", message: `altool (active AL extension ${altool.version || "unknown version"}): ${altool.binary}` });
    } else if (altool.state === "missingBinary") {
        findings.push({ level: "warning", message: `The active AL extension has no bin\\altool.exe or bin\\win32\\altool.exe: ${altool.extensionPath}` });
    } else {
        findings.push({ level: "info", message: "AL extension (ms-dynamics-smb.al) is not installed; the starter searches installed extensions and the dotnet tool 'al' on PATH itself." });
    }

    for (const file of findDuplicateRegistrations()) {
        findings.push({ level: "warning", message: `Duplicate AL MCP registration: ${file} contains 'launchmcpserver'. Remove it; the Aproda extension provides the al-mcp server.` });
    }

    const autostart = vscode.workspace.getConfiguration("chat.mcp").get<string>("autostart");
    if (mode === "auto" && autostart === "never" && !ownStartPathConfirmed) {
        findings.push({ level: "warning", message: "aprodaAldc.alMcp.start is 'auto' but chat.mcp.autostart is 'never', and the extension's own start command is not confirmed (Q-23): the AL MCP server may not start until you start it manually." });
    }
    return findings;
}
