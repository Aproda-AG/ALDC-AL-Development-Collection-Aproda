import * as crypto from "crypto";
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { alMcpStartMode, pwshPath } from "../config";
import { resolveAldcRepository } from "../env/gitRoot";
import { Logger } from "../log";
import { isAlWorkspace } from "../workspace/alWorkspace";
import { getAlExtension } from "./altool";
import { credentialStoreDirectory, hasStoredCredential, storeAlCredential } from "./credential";
import { LocalSelection, getLaunchFilePath, getLocalSelection } from "./localSelection";
import { psQuote } from "./psQuote";
import { selectAlTarget } from "./selectTarget";
import { readToolkitInfo } from "./toolkit";

export const providerId = "aprodaAldc.alMcp";
export const serverLabel = "al-mcp";

export interface AlMcpProviderOptions {
    readonly debounceMs?: number;
    readonly notificationWaitMs?: number;
}

interface ProviderContext {
    readonly repositoryRoot: string;
    readonly configurationPath: string;
    readonly starterPath: string;
    readonly skillRoot: string;
    readonly layerVersion: string;
}

// Q-24: every input that changes the fingerprint is listed here and only here. If a changed `version` turns out
// to re-show VS Code's trust dialog, drop the target-dependent entries and restart through restartServer instead.
export interface VersionInputs {
    readonly selectionFileHash: string;
    readonly resolvedLaunchJson: string;
    readonly credentialPresent: boolean;
    readonly alExtensionVersion: string;
    readonly layerVersion: string;
}

export function computeVersion(inputs: VersionInputs): string {
    const parts = [inputs.selectionFileHash, inputs.resolvedLaunchJson, inputs.credentialPresent ? "1" : "0", inputs.alExtensionVersion, inputs.layerVersion];
    return crypto.createHash("sha256").update(JSON.stringify(parts)).digest("hex").slice(0, 12);
}

function collectVersionInputs(context: ProviderContext, selection: LocalSelection): VersionInputs {
    let selectionFileHash = "";
    if (selection.path) {
        try {
            selectionFileHash = crypto.createHash("sha256").update(fs.readFileSync(selection.path)).digest("hex");
        } catch {
            selectionFileHash = "";
        }
    }
    const credentialRelevant = selection.resolvedLaunch?.authentication === "UserPassword";
    return {
        selectionFileHash,
        resolvedLaunchJson: JSON.stringify(selection.resolvedLaunch),
        credentialPresent: credentialRelevant && hasStoredCredential(selection.resolvedLaunch?.credentialKey),
        alExtensionVersion: getAlExtension()?.version ?? "",
        layerVersion: context.layerVersion
    };
}

export function buildStarterCommand(starterPath: string, repositoryRoot: string, skillRoot: string, alExtension: { path: string; version: string } | undefined): string {
    const parts = [
        `& ([ScriptBlock]::Create((Get-Content -LiteralPath ${psQuote(starterPath)} -Raw)))`,
        `-RepositoryRoot ${psQuote(repositoryRoot)}`,
        `-SkillRoot ${psQuote(skillRoot)}`
    ];
    if (alExtension) {
        parts.push(`-AlExtensionPath ${psQuote(alExtension.path)}`);
        if (alExtension.version) {
            parts.push(`-AlExtensionVersion ${psQuote(alExtension.version)}`);
        }
    }
    return parts.join(" ");
}

export class AlMcpProvider implements vscode.McpServerDefinitionProvider<vscode.McpStdioServerDefinition>, vscode.Disposable {
    private readonly emitter = new vscode.EventEmitter<void>();
    readonly onDidChangeMcpServerDefinitions = this.emitter.event;
    private readonly subscriptions: vscode.Disposable[] = [];
    private watchers: vscode.Disposable[] = [];
    private watchKey = "";
    private startRequested = false;
    private timer: ReturnType<typeof setTimeout> | undefined;
    private loggedMissingStarter: string | undefined;
    private readonly debounceMs: number;
    private readonly notificationWaitMs: number;

    constructor(private readonly logger: Logger, options: AlMcpProviderOptions = {}) {
        this.debounceMs = options.debounceMs ?? 500;
        this.notificationWaitMs = options.notificationWaitMs ?? 30_000;
        this.subscriptions.push(
            this.emitter,
            vscode.workspace.onDidChangeWorkspaceFolders(() => this.scheduleRefresh()),
            vscode.workspace.onDidChangeConfiguration((event) => {
                if (event.affectsConfiguration("aprodaAldc.alMcp.start")) {
                    this.scheduleRefresh();
                }
            }),
            vscode.extensions.onDidChange(() => this.scheduleRefresh())
        );
    }

    isStartRequested(): boolean {
        return this.startRequested;
    }

    // Manual mode: the window-scoped flag that makes provideMcpServerDefinitions return the definition (spec §4.3a).
    requestStart(): void {
        this.startRequested = true;
        this.emitter.fire();
    }

    scheduleRefresh(): void {
        if (this.timer) {
            clearTimeout(this.timer);
        }
        this.timer = setTimeout(() => {
            this.timer = undefined;
            this.emitter.fire();
        }, this.debounceMs);
    }

    // Immediate announcement, used right before a start so VS Code knows the definition.
    refreshNow(): void {
        if (this.timer) {
            clearTimeout(this.timer);
            this.timer = undefined;
        }
        this.emitter.fire();
    }

    async provideMcpServerDefinitions(): Promise<vscode.McpStdioServerDefinition[]> {
        if (!isAlWorkspace()) {
            return [];
        }
        if (alMcpStartMode() === "manual" && !this.startRequested) {
            return [];
        }
        const context = await this.resolveContext();
        if (!context) {
            return [];
        }
        const selection = getLocalSelection(context.repositoryRoot);
        this.ensureWatchers(context, selection);

        const alExtension = getAlExtension();
        const args = [
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            buildStarterCommand(context.starterPath, context.repositoryRoot, context.skillRoot, alExtension)
        ];
        // env stays empty: the extension never passes target or credential values to the server.
        const definition = new vscode.McpStdioServerDefinition(serverLabel, pwshPath(), args, {}, computeVersion(collectVersionInputs(context, selection)));
        definition.cwd = vscode.Uri.file(context.repositoryRoot);
        return [definition];
    }

    async resolveMcpServerDefinition(server: vscode.McpStdioServerDefinition, token: vscode.CancellationToken): Promise<vscode.McpStdioServerDefinition> {
        const resolution = await resolveAldcRepository();
        if (resolution.state === "configured") {
            await this.notifyTargetProblems(getLocalSelection(resolution.repositoryRoot), token);
        }
        // The extension cannot observe the starter's exit code; VS Code shows the MCP error and keeps the starter's stderr.
        this.logger.info(`Starting ${serverLabel} (version ${server.version ?? "none"}). Starter diagnostics and exit codes: MCP: List Servers > ${serverLabel} > Show Output.`);
        return server;
    }

    dispose(): void {
        if (this.timer) {
            clearTimeout(this.timer);
            this.timer = undefined;
        }
        for (const watcher of this.watchers) {
            watcher.dispose();
        }
        this.watchers = [];
        for (const subscription of this.subscriptions) {
            subscription.dispose();
        }
    }

    private async resolveContext(): Promise<ProviderContext | undefined> {
        const resolution = await resolveAldcRepository();
        if (resolution.state !== "configured") {
            return undefined;
        }
        const info = readToolkitInfo(resolution.repositoryRoot, resolution.configurationPath);
        const skillRoot = info.toolkitRoot ? path.join(info.toolkitRoot, "skills", "skill-aproda-al-mcp") : undefined;
        const starterPath = skillRoot ? path.join(skillRoot, "scripts", "Start-AprodaAlMcp.ps1") : undefined;
        if (!skillRoot || !starterPath || !fs.existsSync(starterPath)) {
            const expected = starterPath ?? "<toolkitRoot>/skills/skill-aproda-al-mcp/scripts/Start-AprodaAlMcp.ps1";
            if (this.loggedMissingStarter !== expected) {
                this.loggedMissingStarter = expected;
                this.logger.info(`AL MCP server not provided: starter script not found (${expected}). Apply the toolkit to the project.`);
            }
            return undefined;
        }
        this.loggedMissingStarter = undefined;
        return { repositoryRoot: resolution.repositoryRoot, configurationPath: resolution.configurationPath, starterPath, skillRoot, layerVersion: info.layerVersion };
    }

    private ensureWatchers(context: ProviderContext, selection: LocalSelection): void {
        const launchPath = selection.target ? getLaunchFilePath(context.repositoryRoot, selection.target.launchProject) : undefined;
        const credentialDirectory = credentialStoreDirectory();
        const targets = [selection.path, launchPath, context.configurationPath].filter((value): value is string => !!value)
            .map((filePath) => ({ base: path.dirname(filePath), pattern: path.basename(filePath) }));
        if (credentialDirectory) {
            targets.push({ base: credentialDirectory, pattern: "*.cred.xml" });
        }
        const key = JSON.stringify(targets);
        if (key === this.watchKey) {
            return;
        }
        for (const watcher of this.watchers) {
            watcher.dispose();
        }
        this.watchKey = key;
        this.watchers = targets.map((target) => {
            const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(vscode.Uri.file(target.base), target.pattern));
            const onEvent = (): void => this.scheduleRefresh();
            watcher.onDidChange(onEvent);
            watcher.onDidCreate(onEvent);
            watcher.onDidDelete(onEvent);
            return watcher;
        });
    }

    // Spec §4.3 resolve table. The definition is always returned; the choice only decides what happens first.
    private async notifyTargetProblems(selection: LocalSelection, token: vscode.CancellationToken): Promise<void> {
        if (selection.state !== "configured") {
            const choice = await this.waitForChoice(
                vscode.window.showWarningMessage("No valid AL target for AL MCP.", "Select target", "Start build-only"), token);
            if (choice === "Select target") {
                await this.waitForChoice(selectAlTarget(this.logger), token);
            }
            return;
        }
        if (selection.issues.length > 0) {
            void vscode.window.showWarningMessage(
                `The selected AL target '${selection.resolvedLaunch?.name ?? ""}' is blocked for target operations (${selection.issues.map((issue) => issue.code).join(", ")}). AL MCP starts build-only.`);
            return;
        }
        const resolved = selection.resolvedLaunch;
        if (resolved?.authentication === "UserPassword" && !hasStoredCredential(resolved.credentialKey)) {
            const choice = await this.waitForChoice(
                vscode.window.showWarningMessage(`No stored credential for ${resolved.credentialKey}.`, "Store credential", "Start build-only"), token);
            if (choice === "Store credential") {
                await this.waitForChoice(storeAlCredential(this.logger), token);
            }
        }
    }

    // A notification the user ignores must not hold the server start hostage: cancellation and a time limit end the wait.
    private waitForChoice<T>(pending: Thenable<T>, token: vscode.CancellationToken): Promise<T | undefined> {
        return new Promise((resolve) => {
            let timeout: ReturnType<typeof setTimeout> | undefined;
            let cancellation: vscode.Disposable | undefined;
            const finish = (value: T | undefined): void => {
                if (timeout) {
                    clearTimeout(timeout);
                }
                cancellation?.dispose();
                resolve(value);
            };
            timeout = setTimeout(() => finish(undefined), this.notificationWaitMs);
            cancellation = token.onCancellationRequested(() => finish(undefined));
            Promise.resolve(pending).then(finish, () => finish(undefined));
        });
    }
}
