import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { autoReconcileBcquality, setBcqualityEnvInWorkspace } from "../config";
import { Logger } from "../log";
import { resolveBcquality } from "../bcquality/resolve";

// Junction lives at <repositoryRoot>/.external/bcquality (T-29): the wrapper is tracked and seeded by the syncer,
// the junction itself is git-ignored and extension-managed.
export async function reconcileBcquality(repositoryRoot: string, bcqualityRoot: string, logger: Logger): Promise<void> {
    const resolution = await resolveBcquality();
    const linkPath = path.join(repositoryRoot, ".external", "bcquality");

    if (resolution.enabled === false) {
        // A kill-switch must never strand infrastructure: this runs regardless of the opt-out setting below.
        await removeBcqualityLink(linkPath, logger);
        return;
    }

    if (!autoReconcileBcquality()) {
        // The opt-out only gates the additive work (Global setting + creating a junction).
        return;
    }
    await updateBcqualityHomeGlobalSetting(bcqualityRoot);

    if (!resolution.verified || !resolution.root) {
        // No verified clone yet (the default for a new project): never link to nothing.
        return;
    }
    await createBcqualityLink(linkPath, resolution.root, logger);
}

async function updateBcqualityHomeGlobalSetting(bcqualityRoot: string): Promise<void> {
    if (!setBcqualityEnvInWorkspace()) {
        return;
    }
    const configuration = vscode.workspace.getConfiguration("terminal.integrated.env");
    for (const platform of ["windows", "linux", "osx"] as const) {
        const existing = configuration.get<Record<string, string>>(platform) ?? {};
        await configuration.update(platform, { ...existing, BCQUALITY_HOME: bcqualityRoot }, vscode.ConfigurationTarget.Global);
    }
}

export async function createBcqualityLink(linkPath: string, target: string, logger: Logger): Promise<void> {
    const currentTarget = await readLinkTarget(linkPath);
    if (currentTarget && path.resolve(currentTarget) === path.resolve(target)) {
        return;
    }
    if (currentTarget) {
        await removeBcqualityLink(linkPath, logger);
    }
    await fs.mkdir(path.dirname(linkPath), { recursive: true });
    await fs.symlink(target, linkPath, process.platform === "win32" ? "junction" : "dir");
    logger.info(`Linked BCQuality: ${linkPath} -> ${target}`);
}

async function readLinkTarget(linkPath: string): Promise<string | undefined> {
    try {
        const stats = await fs.lstat(linkPath);
        if (!stats.isSymbolicLink()) {
            return undefined;
        }
        return (await fs.readlink(linkPath)).replace(/^\\\\\?\\/, "");
    } catch {
        return undefined;
    }
}

// Removes only the link, never its target: lstat first, and unlink/rmdir the reparse point without following it.
export async function removeBcqualityLink(linkPath: string, logger: Logger): Promise<void> {
    let stats;
    try {
        stats = await fs.lstat(linkPath);
    } catch {
        return;
    }
    if (!stats.isSymbolicLink()) {
        logger.error(`Refusing to remove ${linkPath}: not a link.`);
        return;
    }
    if (process.platform === "win32") {
        await fs.rmdir(linkPath);
    } else {
        await fs.unlink(linkPath);
    }
    logger.info(`Removed BCQuality link: ${linkPath}`);
}