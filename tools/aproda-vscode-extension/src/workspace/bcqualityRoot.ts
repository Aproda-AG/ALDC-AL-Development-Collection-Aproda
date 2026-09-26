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
        logger.info("BCQuality is disabled in aldc.yaml; removing any existing link.");
        await removeBcqualityLink(linkPath, logger);
        return;
    }

    if (!autoReconcileBcquality()) {
        // The opt-out only gates the additive work (Global setting + creating a junction).
        logger.info("BCQuality reconciliation is switched off (bcquality.autoReconcile); leaving the workspace unchanged.");
        return;
    }
    // The env var and the junction must not be two independently resolved answers: the caller's value
    // was resolved earlier and can already be stale by now.
    await updateBcqualityHomeGlobalSetting(resolution.verified && resolution.root ? resolution.root : bcqualityRoot);

    if (!resolution.verified || !resolution.root) {
        // No verified clone yet (the default for a new project): never link to nothing.
        logger.info("BCQuality did not resolve to a verified clone; no link created.");
        return;
    }
    await createBcqualityLink(linkPath, resolution.root, logger);
}

const terminalEnvPlatforms = ["windows", "linux", "osx"] as const;
type TerminalEnvPlatform = typeof terminalEnvPlatforms[number];

function currentTerminalEnvPlatform(): TerminalEnvPlatform {
    if (process.platform === "win32") {
        return "windows";
    }
    if (process.platform === "darwin") {
        return "osx";
    }
    return "linux";
}

// The resolved clone path is machine-local: it must only ever land under the platform actually running,
// never under terminal.integrated.env.linux/.osx on Windows (or vice versa).
async function updateBcqualityHomeGlobalSetting(bcqualityRoot: string): Promise<void> {
    if (!setBcqualityEnvInWorkspace()) {
        return;
    }
    const configuration = vscode.workspace.getConfiguration("terminal.integrated.env");
    const activePlatform = currentTerminalEnvPlatform();
    for (const platform of terminalEnvPlatforms) {
        // Read the Global layer explicitly: the effective (workspace+global merged) value must never be
        // written back to Global, or a workspace-scoped variable would be silently promoted to it.
        const existingGlobal = configuration.inspect<Record<string, string>>(platform)?.globalValue ?? {};
        if (platform === activePlatform) {
            await configuration.update(platform, { ...existingGlobal, BCQUALITY_HOME: bcqualityRoot }, vscode.ConfigurationTarget.Global);
            continue;
        }
        if (!("BCQUALITY_HOME" in existingGlobal)) {
            continue;
        }
        const { BCQUALITY_HOME: _unused, ...rest } = existingGlobal;
        await configuration.update(platform, Object.keys(rest).length > 0 ? rest : undefined, vscode.ConfigurationTarget.Global);
    }
}

export async function createBcqualityLink(linkPath: string, target: string, logger: Logger): Promise<void> {
    if (await targetResolvesToLink(target, linkPath)) {
        logger.error(`Refusing to link BCQuality to itself: ${target} resolves to ${linkPath}.`);
        return;
    }
    const currentTarget = await readLinkTarget(linkPath);
    if (currentTarget && path.resolve(currentTarget) === path.resolve(target)) {
        logger.info(`BCQuality link already correct: ${linkPath} -> ${target}`);
        return;
    }
    if (currentTarget) {
        await removeBcqualityLink(linkPath, logger);
    }
    await fs.mkdir(path.dirname(linkPath), { recursive: true });
    await fs.symlink(target, linkPath, process.platform === "win32" ? "junction" : "dir");
    logger.info(`Linked BCQuality: ${linkPath} -> ${target}`);
}

// Defence in depth for Fix A (resolve.ts already canonicalises verified candidates): even if a future
// resolver change reintroduces a link-as-root, no self-referential junction can be created here.
// Both sides are canonicalised (when possible) before comparing, because Windows can otherwise report
// linkPath in its 8.3 short-name form (e.g. via os.tmpdir()) while realpath() on target expands it to the
// long form, making an actual self-reference look like a difference. realpath() on linkPath is safe here:
// if linkPath is currently a self-referential junction it throws ELOOP, which is caught and degrades to a
// plain path.resolve() comparison rather than crashing.
async function targetResolvesToLink(target: string, linkPath: string): Promise<boolean> {
    if (path.resolve(target) === path.resolve(linkPath)) {
        return true;
    }
    const resolvedLinkPath = await canonicalOrResolved(linkPath);
    const resolvedTarget = await canonicalOrResolved(target);
    return resolvedTarget === resolvedLinkPath;
}

async function canonicalOrResolved(candidatePath: string): Promise<string> {
    try {
        return path.resolve((await fs.realpath(candidatePath)).replace(/^\\\\\?\\/, ""));
    } catch {
        return path.resolve(candidatePath);
    }
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