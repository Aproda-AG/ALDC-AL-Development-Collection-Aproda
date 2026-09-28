import * as fs from "fs/promises";
import { parse } from "yaml";
import { branchName, channel, Channel, repositoryUrl, sourceMode } from "../config";
import { resolveConfigurationPath } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";
import { compareLayerVersions, isLayerVersion, VersionComparison } from "./compare";

export type LayerUpdateStatus = "notInstalled" | "current" | "outdated" | "ahead" | "invalid" | "unavailable" | "unknown";

export interface LayerUpdateResult {
    readonly status: LayerUpdateStatus;
    readonly installed?: string;
    readonly available?: string;
    readonly comparison?: VersionComparison;
    readonly message: string;
}

interface ConfiguredFields {
    readonly layerVersion?: string;
    readonly appliedRef?: string;
}

export class VersionService {
    constructor(private readonly logger: Logger) { }

    // Channel-aware per D-50: `release` compares tags, `edge`/`branch` compare commit SHAs against
    // `aproda.appliedRef`, `pinned`/`localFork` never report an update. The "is it installed at all"
    // gate (aldc.yaml presence) runs before any of that, regardless of channel or source mode.
    async check(repoRoot: string): Promise<LayerUpdateResult> {
        const configPath = await resolveConfigurationPath(repoRoot);
        if (!configPath) {
            this.logger.info(`Could not find aldc.yaml under ${repoRoot} (checked .github/aldc.yaml and aldc.yaml).`);
            return { status: "notInstalled", message: "Aproda ALDC is not installed in this project." };
        }
        const fields = await this.readConfiguredFields(configPath);

        if (sourceMode() === "localFork") {
            return { status: "current", installed: fields.layerVersion, message: "Source mode is a local fork; toolkit update checks do not apply." };
        }

        const currentChannel = channel();
        if (currentChannel === "pinned") {
            return { status: "current", installed: fields.layerVersion, message: "Toolkit channel is pinned; update checks do not apply." };
        }
        if (currentChannel === "release") {
            if (!fields.layerVersion) {
                return { status: "notInstalled", message: "Aproda ALDC is not installed in this project." };
            }
            return this.checkRelease(fields.layerVersion);
        }
        return this.checkMovingChannel(currentChannel, fields.appliedRef);
    }

    private async checkRelease(installed: string): Promise<LayerUpdateResult> {
        if (!isLayerVersion(installed)) {
            return { status: "invalid", installed, message: `Cannot compare installed toolkit version "${installed}".` };
        }

        const available = await this.readAvailableReleaseTag();
        if (!available) {
            return { status: "unavailable", installed, message: "No tagged Aproda ALDC release is available from the configured repository." };
        }
        const comparison = compareLayerVersions(installed, available);
        if (comparison === undefined) {
            return { status: "invalid", installed, available, message: "Cannot compare Aproda ALDC toolkit versions." };
        }
        if (comparison < 0) {
            return { status: "outdated", installed, available, comparison, message: `Aproda ALDC update available: ${installed} -> ${available}.` };
        }
        if (comparison > 0) {
            return { status: "ahead", installed, available, comparison, message: `Installed Aproda ALDC version ${installed} is newer than the latest tagged release ${available}.` };
        }
        return { status: "current", installed, available, comparison, message: `Aproda ALDC is up to date (${installed}).` };
    }

    // `edge`/`branch` only: never consults isLayerVersion/compareLayerVersions, which are tag-shaped
    // and would otherwise reject every SHA as "invalid" forever.
    private async checkMovingChannel(currentChannel: Extract<Channel, "edge" | "branch">, appliedRef: string | undefined): Promise<LayerUpdateResult> {
        const repository = repositoryUrl();
        if (!repository) {
            throw new Error("The Aproda ALDC repository URL is not configured.");
        }

        let ref: string;
        if (currentChannel === "edge") {
            ref = "refs/heads/aproda";
        } else {
            const branch = branchName();
            if (!branch) {
                throw new Error("Set Aproda ALDC: Branch Name before checking the branch channel for updates.");
            }
            ref = `refs/heads/${branch}`;
        }

        const available = await this.readRemoteSha(repository, ref);
        if (!available) {
            // Branch deleted/renamed, or a network/git failure -- both must read as "unavailable",
            // never as a silent "current" (B-6).
            return {
                status: "unavailable",
                installed: appliedRef,
                message: `Could not determine the latest commit on ${ref} at ${repository}. Check the branch name and Git access.`
            };
        }

        if (!appliedRef) {
            // First switch to edge/branch: nothing has been applied on this channel yet. Not
            // "current", not an invented update, and not "invalid" -- resolved by the next apply.
            return {
                status: "unknown",
                available: shortSha(available),
                message: "Aproda ALDC has not recorded an applied commit for this channel yet. Apply the toolkit once to establish a baseline."
            };
        }

        if (appliedRef === available) {
            return { status: "current", installed: shortSha(appliedRef), available: shortSha(available), message: `Aproda ALDC is up to date (${shortSha(appliedRef)}).` };
        }
        return {
            status: "outdated",
            installed: shortSha(appliedRef),
            available: shortSha(available),
            message: `Aproda ALDC update available: ${shortSha(appliedRef)} -> ${shortSha(available)}.`
        };
    }

    private async readConfiguredFields(configPath: string): Promise<ConfiguredFields> {
        try {
            const document = parse(await fs.readFile(configPath, "utf8")) as { aproda?: { layerVersion?: unknown; appliedRef?: unknown } } | null;
            const layerVersion = document?.aproda?.layerVersion;
            const appliedRef = document?.aproda?.appliedRef;
            return {
                layerVersion: typeof layerVersion === "string" ? layerVersion.trim() : undefined,
                appliedRef: typeof appliedRef === "string" ? appliedRef.trim() : undefined
            };
        } catch (error) {
            this.logger.info(`Could not read Aproda ALDC configuration from ${configPath}: ${asMessage(error)}`);
            return {};
        }
    }

    private async readAvailableReleaseTag(): Promise<string | undefined> {
        const repository = repositoryUrl();
        if (!repository) {
            throw new Error("The Aproda ALDC repository URL is not configured.");
        }
        this.logger.info(`Checking toolkit release tags: ${repository}`);
        const result = await run("git", ["ls-remote", "--tags", repository, "refs/tags/v*_aproda.*"], {
            env: { GIT_TERMINAL_PROMPT: "0" }
        });
        if (result.code !== 0) {
            this.logger.error(result.stderr.trim() || result.stdout.trim());
            throw new Error("Could not query Aproda ALDC release tags.");
        }

        const latest = result.stdout.split(/\r?\n/)
            .map((line) => line.trim().split(/\s+/).at(-1) ?? "")
            .map((reference) => reference.replace("refs/tags/v", ""))
            .filter(isLayerVersion)
            .sort((left, right) => compareLayerVersions(left, right) ?? 0)
            .at(-1);
        if (latest) {
            this.logger.info(`Latest tagged toolkit version: ${latest}`);
        }
        return latest;
    }

    // The remote tip only (git ls-remote) -- never the managed cache: a fetch plus checkout on every
    // window start would race a concurrently running Apply Toolkit (D-50 §3.2).
    private async readRemoteSha(repository: string, ref: string): Promise<string | undefined> {
        this.logger.info(`Checking toolkit channel tip: ${repository} ${ref}`);
        let result;
        try {
            result = await run("git", ["ls-remote", repository, ref], { env: { GIT_TERMINAL_PROMPT: "0" } });
        } catch (error) {
            this.logger.error(asMessage(error));
            return undefined;
        }
        if (result.code !== 0) {
            this.logger.error(result.stderr.trim() || result.stdout.trim());
            return undefined;
        }
        const line = result.stdout.split(/\r?\n/).find((entry) => entry.trim().length > 0);
        const sha = line?.trim().split(/\s+/)[0];
        if (sha) {
            this.logger.info(`Latest commit on ${ref}: ${sha}`);
        }
        return sha;
    }
}

function asMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}

// Comparisons above always use the full SHA; only the display message is shortened.
function shortSha(value: string): string {
    return /^[0-9a-f]{40}$/i.test(value) ? value.slice(0, 8) : value;
}
