import * as fs from "fs/promises";
import * as https from "https";
import * as vscode from "vscode";
import { repositoryUrl } from "../config";
import { Logger } from "../log";
import { run } from "../process";
import { compareExtensionVersions } from "./version";

const tagPrefix = "vscode-ext/v";
const versionPattern = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

export interface ExtensionUpdate {
    readonly current: string;
    readonly available: string;
    readonly tag: string;
}

interface GitHubRelease {
    readonly assets: ReadonlyArray<{ name: string; url: string }>;
}

export async function findExtensionUpdate(logger: Logger): Promise<ExtensionUpdate | undefined> {
    const current = currentExtensionVersion();
    const repository = repositoryUrl();
    const result = await run("git", ["ls-remote", "--tags", repository, "refs/tags/vscode-ext/v*"], {
        env: { GIT_TERMINAL_PROMPT: "0" }
    });
    if (result.code !== 0) {
        logger.error(result.stderr.trim() || result.stdout.trim());
        throw new Error("Could not query Aproda ALDC extension release tags.");
    }

    const available = result.stdout.split(/\r?\n/)
        .map((line) => line.trim().split(/\s+/).at(-1) ?? "")
        .map((reference) => reference.replace("refs/tags/", ""))
        .filter((tag) => tag.startsWith(tagPrefix) && versionPattern.test(tag.slice(tagPrefix.length)))
        .map((tag) => ({ tag, version: tag.slice(tagPrefix.length) }))
        .sort((left, right) => compareExtensionVersions(left.version, right.version))
        .at(-1);

    if (!available || compareExtensionVersions(current, available.version) >= 0) {
        return undefined;
    }
    return { current, available: available.version, tag: available.tag };
}

export async function installExtensionUpdate(context: vscode.ExtensionContext, update: ExtensionUpdate, logger: Logger): Promise<void> {
    const repository = githubRepository(repositoryUrl());
    if (!repository) {
        throw new Error("Extension self-update requires a GitHub repository URL.");
    }

    const session = await vscode.authentication.getSession("github", ["repo"], { createIfNone: true });
    const releaseUrl = `https://api.github.com/repos/${repository.owner}/${repository.name}/releases/tags/${encodeURIComponent(update.tag)}`;
    const release = JSON.parse((await request(releaseUrl, session.accessToken)).toString("utf8")) as GitHubRelease;
    const vsixName = `aproda-aldc-${update.available}.vsix`;
    const asset = release.assets.find((candidate) => candidate.name === vsixName);
    if (!asset) {
        throw new Error(`Release ${update.tag} does not contain ${vsixName}.`);
    }

    const updateDirectory = vscode.Uri.joinPath(context.globalStorageUri, "extension-updates");
    await fs.mkdir(updateDirectory.fsPath, { recursive: true });
    const target = vscode.Uri.joinPath(updateDirectory, `aproda-aldc-${update.available}.vsix`);
    await fs.writeFile(target.fsPath, await request(asset.url, session.accessToken, "application/octet-stream"));
    logger.info(`Installing Aproda ALDC extension update ${update.current} -> ${update.available}.`);
    await vscode.commands.executeCommand("workbench.extensions.installExtension", target);
}

function currentExtensionVersion(): string {
    const extension = vscode.extensions.getExtension("aprodaag.aproda-aldc");
    const version = extension?.packageJSON.version;
    if (typeof version !== "string" || !versionPattern.test(version)) {
        throw new Error("Could not determine the installed Aproda ALDC extension version.");
    }
    return version;
}

function githubRepository(repository: string): { owner: string; name: string } | undefined {
    const match = repository.match(/github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?$/i);
    return match ? { owner: match[1], name: match[2] } : undefined;
}

function request(url: string, accessToken: string, accept = "application/vnd.github+json", redirects = 3): Promise<Buffer> {
    return new Promise((resolve, reject) => {
        const isGitHubApi = new URL(url).hostname === "api.github.com";
        const requestHeaders: Record<string, string> = { Accept: accept, "User-Agent": "aproda-aldc-vscode-extension" };
        if (isGitHubApi) {
            requestHeaders.Authorization = `Bearer ${accessToken}`;
        }
        https.get(url, { headers: requestHeaders }, (response) => {
            const location = response.headers.location;
            if (response.statusCode && response.statusCode >= 300 && response.statusCode < 400 && location && redirects > 0) {
                response.resume();
                void request(new URL(location, url).toString(), accessToken, accept, redirects - 1).then(resolve, reject);
                return;
            }
            const chunks: Buffer[] = [];
            response.on("data", (chunk: Buffer) => chunks.push(chunk));
            response.on("end", () => {
                if (response.statusCode !== 200) {
                    reject(new Error(`GitHub request failed with HTTP ${response.statusCode ?? "unknown"}: ${Buffer.concat(chunks).toString("utf8")}`));
                    return;
                }
                resolve(Buffer.concat(chunks));
            });
        }).on("error", reject);
    });
}