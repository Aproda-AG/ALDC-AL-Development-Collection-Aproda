import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { channel, forkPath, pinnedVersion, repositoryUrl, sourceMode } from "../config";
import { Logger } from "../log";
import { run } from "../process";

export interface SourceStatus {
    readonly mode: "managed" | "localFork";
    readonly path: string;
    readonly reference?: string;
    readonly message: string;
}

export class LayerSource {
    private readonly cachePath: string;

    constructor(private readonly context: vscode.ExtensionContext, private readonly logger: Logger) {
        this.cachePath = path.join(context.globalStorageUri.fsPath, "layer-cache", "fork");
    }

    async ensure(): Promise<SourceStatus> {
        if (sourceMode() === "localFork") {
            return this.ensureLocalFork();
        }

        return this.ensureManagedCache();
    }

    async repair(): Promise<void> {
        if (sourceMode() === "localFork") {
            throw new Error("Repair Layer Cache is available only in managed source mode.");
        }

        this.logger.info(`Removing managed layer cache: ${this.cachePath}`);
        await fs.rm(this.cachePath, { recursive: true, force: true });
        await this.ensureManagedCache();
    }

    async describe(): Promise<SourceStatus> {
        if (sourceMode() === "localFork") {
            return this.ensureLocalFork(false);
        }

        const exists = await pathExists(path.join(this.cachePath, ".git"));
        return {
            mode: "managed",
            path: this.cachePath,
            message: exists ? "Managed cache is available." : "Managed cache has not been created yet."
        };
    }

    private async ensureManagedCache(): Promise<SourceStatus> {
        const repository = repositoryUrl();
        if (!repository) {
            throw new Error("The managed layer repository URL is not configured.");
        }

        await fs.mkdir(path.dirname(this.cachePath), { recursive: true });
        if (!await pathExists(path.join(this.cachePath, ".git"))) {
            await this.cloneManagedCache(repository);
        }

        await this.git(["fetch", "--tags", "--prune"], this.cachePath, false);
        const reference = await this.resolveReference(this.cachePath);
        await this.git(["checkout", "--detach", reference], this.cachePath, false);
        await this.git(["reset", "--hard", reference], this.cachePath, false);
        await this.git(["clean", "-xfd"], this.cachePath, false);
        this.logger.info(`Managed layer cache is ready at ${this.cachePath} (${reference}).`);

        return {
            mode: "managed",
            path: this.cachePath,
            reference,
            message: "Managed cache is ready."
        };
    }

    private async cloneManagedCache(repository: string): Promise<void> {
        this.logger.info("Creating managed layer cache using stored Git credentials.");
        const initialClone = await run("git", ["clone", "--no-checkout", "--filter=blob:none", repository, this.cachePath], {
            env: { GIT_TERMINAL_PROMPT: "0" }
        });
        if (initialClone.code === 0) {
            this.logger.info("Managed layer cache clone completed without interactive authentication.");
            return;
        }

        this.logger.info(initialClone.stderr.trim() || initialClone.stdout.trim());
        const terminal = vscode.window.createTerminal({ name: "Aproda ALDC: Authenticate Layer Source" });
        const command = [
            `$ErrorActionPreference = 'Stop'`,
            `Remove-Item -LiteralPath ${psQuote(this.cachePath)} -Recurse -Force -ErrorAction SilentlyContinue`,
            `New-Item -ItemType Directory -Force -Path ${psQuote(path.dirname(this.cachePath))} | Out-Null`,
            `git clone --no-checkout --filter=blob:none ${psQuote(repository)} ${psQuote(this.cachePath)}`
        ].join("; ");

        this.logger.info("Opening a terminal for the initial managed-cache clone.");
        terminal.show(true);
        terminal.sendText(`pwsh -NoProfile -Command ${psQuote(command)}`, true);
        const selection = await vscode.window.showInformationMessage(
            "Git credentials were not available for the managed layer cache. Complete authentication in the Aproda ALDC terminal, then run Repair Layer Cache again.",
            "Show Log"
        );
        if (selection === "Show Log") {
            this.logger.show();
        }
        throw new Error("Managed-cache clone requires Git authentication. Complete the terminal command, then run Repair Layer Cache again.");
    }

    private async ensureLocalFork(validate = true): Promise<SourceStatus> {
        const localPath = forkPath();
        if (!localPath) {
            throw new Error("Set Aproda ALDC: Source Fork Path before using localFork mode.");
        }
        if (!await pathExists(path.join(localPath, ".git"))) {
            throw new Error(`Local fork is not a Git repository: ${localPath}`);
        }
        if (!await pathExists(path.join(localPath, "tools", "aproda-sync", "Bootstrap-AprodaProject.ps1"))) {
            throw new Error(`Local fork does not contain the Aproda sync engine: ${localPath}`);
        }

        if (validate) {
            const status = await this.git(["status", "--porcelain"], localPath, true);
            if (status.stdout.trim()) {
                await vscode.window.showWarningMessage("The local Aproda fork has uncommitted changes.", "Show Log").then((selection) => {
                    if (selection === "Show Log") {
                        this.logger.show();
                    }
                });
            }
            const branch = await this.git(["branch", "--show-current"], localPath, true);
            if (branch.stdout.trim() !== "aproda") {
                await vscode.window.showWarningMessage(`The local Aproda fork is on "${branch.stdout.trim() || "detached HEAD"}", not "aproda".`);
            }
            const behind = await this.git(["rev-list", "--count", "HEAD..@{upstream}"], localPath, true);
            if (behind.code === 0 && Number(behind.stdout.trim()) > 0) {
                await vscode.window.showWarningMessage(`The local Aproda fork is ${behind.stdout.trim()} commit(s) behind its upstream.`);
            }
        }

        return { mode: "localFork", path: localPath, message: "Local fork is ready." };
    }

    private async resolveReference(cwd: string): Promise<string> {
        if (channel() === "edge") {
            return "origin/aproda";
        }
        if (channel() === "pinned") {
            const version = pinnedVersion();
            if (!version) {
                throw new Error("Set Aproda ALDC: Pinned Version before using the pinned channel.");
            }
            return `v${version}`;
        }

        const tags = await this.git(["tag", "--list", "v*_aproda.*"], cwd, false);
        const latest = tags.stdout.trim().split(/\r?\n/).filter(Boolean).sort(compareLayerTags).at(-1);
        if (!latest) {
            throw new Error("No Aproda layer release tags were found in the managed cache.");
        }
        return latest;
    }

    private async git(args: readonly string[], cwd: string, allowFailure: boolean): Promise<{ code: number; stdout: string; stderr: string }> {
        this.logger.info(`git ${args.join(" ")} (${cwd})`);
        const result = await run("git", [...args], { cwd, env: { GIT_TERMINAL_PROMPT: "0" } });
        if (result.code !== 0 && !allowFailure) {
            this.logger.error(result.stderr || result.stdout);
            throw new Error(`Git command failed: git ${args.join(" ")}`);
        }
        if (result.stdout.trim()) {
            this.logger.info(result.stdout.trim());
        }
        if (result.stderr.trim()) {
            this.logger.info(result.stderr.trim());
        }
        return result;
    }
}

function psQuote(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
}

async function pathExists(candidate: string): Promise<boolean> {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}

function compareLayerTags(left: string, right: string): number {
    const toParts = (tag: string): number[] => {
        const match = /^v(\d+)\.(\d+)\.(\d+)_aproda\.(\d+)$/.exec(tag);
        return match ? match.slice(1).map(Number) : [0, 0, 0, 0];
    };
    const leftParts = toParts(left);
    const rightParts = toParts(right);
    for (let index = 0; index < leftParts.length; index += 1) {
        if (leftParts[index] !== rightParts[index]) {
            return leftParts[index] - rightParts[index];
        }
    }
    return 0;
}
