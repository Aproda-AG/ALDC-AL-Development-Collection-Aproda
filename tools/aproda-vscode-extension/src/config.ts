import * as vscode from "vscode";

export type SourceMode = "managed" | "localFork";
export type Channel = "release" | "edge" | "pinned";

const section = "aprodaAldc";

export const globalSettingKeys = [
    "devRoot",
    "bcquality.path",
    "bcquality.setEnvInWorkspace",
    "bcquality.autoFixWorkspacePath",
    "gettingStartedUrl",
    "source.mode",
    "source.forkPath",
    "source.repositoryUrl",
    "channel",
    "pinnedVersion",
    "pwshPath",
    "startupCheck.enabled",
    "startupCheck.intervalHours"
] as const;

export function devRoot(): string {
    return vscode.workspace.getConfiguration(section).get<string>("devRoot", "").trim();
}

export function bcqualityPath(): string {
    return vscode.workspace.getConfiguration(section).get<string>("bcquality.path", "").trim();
}

export function setBcqualityEnvInWorkspace(): boolean {
    return vscode.workspace.getConfiguration(section).get<boolean>("bcquality.setEnvInWorkspace", true);
}

export function autoFixBcqualityWorkspacePath(): boolean {
    return vscode.workspace.getConfiguration(section).get<boolean>("bcquality.autoFixWorkspacePath", true);
}

export function gettingStartedUrl(): string {
    return vscode.workspace.getConfiguration(section).get<string>("gettingStartedUrl", "").trim();
}

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

export async function resetGlobalSettings(): Promise<void> {
    const configuration = vscode.workspace.getConfiguration(section);
    await Promise.all(globalSettingKeys.map((key) => configuration.update(key, undefined, vscode.ConfigurationTarget.Global)));
}
