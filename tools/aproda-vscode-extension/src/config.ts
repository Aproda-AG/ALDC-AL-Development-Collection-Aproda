import * as vscode from "vscode";

export type SourceMode = "managed" | "localFork";
export type Channel = "release" | "edge" | "pinned";

const section = "aprodaAldc";

export function sourceMode(): SourceMode {
    return vscode.workspace.getConfiguration(section).get<SourceMode>("source.mode", "managed");
}

export function forkPath(): string {
    return vscode.workspace.getConfiguration(section).get<string>("source.forkPath", "").trim();
}

export function repositoryUrl(): string {
    return vscode.workspace.getConfiguration(section).get<string>("source.repositoryUrl", "").trim();
}

export function channel(): Channel {
    return vscode.workspace.getConfiguration(section).get<Channel>("channel", "release");
}

export function pinnedVersion(): string {
    return vscode.workspace.getConfiguration(section).get<string>("pinnedVersion", "").trim();
}

export function pwshPath(): string {
    return vscode.workspace.getConfiguration(section).get<string>("pwshPath", "pwsh").trim() || "pwsh";
}

export function startupChecksEnabled(): boolean {
    return vscode.workspace.getConfiguration(section).get<boolean>("startupCheck.enabled", true);
}

export function startupCheckIntervalHours(): number {
    return vscode.workspace.getConfiguration(section).get<number>("startupCheck.intervalHours", 24);
}

export function updateGlobal<T>(key: string, value: T): Thenable<void> {
    return vscode.workspace.getConfiguration(section).update(key, value, vscode.ConfigurationTarget.Global);
}
