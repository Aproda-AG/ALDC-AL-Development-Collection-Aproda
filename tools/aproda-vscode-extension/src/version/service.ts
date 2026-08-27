import * as fs from "fs/promises";
import * as path from "path";
import { parse } from "yaml";
import { repositoryUrl } from "../config";
import { Logger } from "../log";
import { run } from "../process";
import { compareLayerVersions, isLayerVersion, VersionComparison } from "./compare";

export type LayerUpdateStatus = "notInstalled" | "current" | "outdated" | "ahead" | "invalid" | "unavailable";

export interface LayerUpdateResult {
    readonly status: LayerUpdateStatus;
    readonly installed?: string;
    readonly available?: string;
    readonly comparison?: VersionComparison;
    readonly message: string;
}

export class VersionService {
    constructor(private readonly logger: Logger) { }

    async check(repoRoot: string): Promise<LayerUpdateResult> {
        const installed = await this.readInstalled(repoRoot);
        if (!installed) {
            return { status: "notInstalled", message: "Aproda ALDC is not installed in this project." };
        }
        if (!isLayerVersion(installed)) {
            return { status: "invalid", installed, message: `Cannot compare installed layer version "${installed}".` };
        }

        const available = await this.readAvailable();
        if (!available) {
            return { status: "unavailable", installed, message: "No tagged Aproda ALDC release is available from the configured repository." };
        }
        const comparison = compareLayerVersions(installed, available);
        if (comparison === undefined) {
            return { status: "invalid", installed, available, message: "Cannot compare Aproda ALDC layer versions." };
        }
        if (comparison < 0) {
            return { status: "outdated", installed, available, comparison, message: `Aproda ALDC update available: ${installed} -> ${available}.` };
        }
        if (comparison > 0) {
            return { status: "ahead", installed, available, comparison, message: `Installed Aproda ALDC version ${installed} is newer than the latest tagged release ${available}.` };
        }
        return { status: "current", installed, available, comparison, message: `Aproda ALDC is up to date (${installed}).` };
    }

    private async readInstalled(repoRoot: string): Promise<string | undefined> {
        const configPath = path.join(repoRoot, "aldc.yaml");
        try {
            const document = parse(await fs.readFile(configPath, "utf8")) as { aproda?: { layerVersion?: unknown } } | null;
            const version = document?.aproda?.layerVersion;
            return typeof version === "string" ? version.trim() : undefined;
        } catch (error) {
            this.logger.info(`Could not read installed layer version from ${configPath}: ${asMessage(error)}`);
            return undefined;
        }
    }

    private async readAvailable(): Promise<string | undefined> {
        const repository = repositoryUrl();
        if (!repository) {
            throw new Error("The Aproda ALDC repository URL is not configured.");
        }
        this.logger.info(`Checking layer release tags: ${repository}`);
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
            this.logger.info(`Latest tagged layer version: ${latest}`);
        }
        return latest;
    }
}

function asMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}
