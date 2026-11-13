import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { autoReconcileBcquality, externalMount, setBcqualityEnvInWorkspace } from "../config";
import { Logger } from "../log";
import { BcqualityResolution, resolveBcquality } from "../bcquality/resolve";
import { migrateWorkspaceFile } from "../external/workspaceMigration";

// Junction lives at <repositoryRoot>/.external/bcquality (T-29): the wrapper is tracked and seeded by the syncer,
// the junction itself is git-ignored and extension-managed (only for external.mount=junction).
export interface ReconcileOptions {
    // Delay before checking that VS Code picked up a migrated workspace file (injectable for tests).
    readonly staleCheckDelayMs?: number;
}

const defaultStaleCheckDelayMs = 3000;

export async function reconcileBcquality(repositoryRoot: string, bcqualityRoot: string, logger: Logger, onReconciled?: () => void, options?: ReconcileOptions): Promise<void> {
    try {
        await reconcileBcqualityCore(repositoryRoot, bcqualityRoot, logger, options);
    } finally {
        onReconciled?.();
    }
}

// VS Code (notably on SMB shares) can keep the old root after the workspace file was rewritten: offer a reload.
async function checkMigrationApplied(logger: Logger, delayMs: number): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, delayMs));
    const folders = vscode.workspace.workspaceFolders ?? [];
    if (folders.some((folder) => folder.uri.scheme === "aldc-external")) {
        logger.info("Workspace migration applied: the aldc-external root is active.");
        return;
    }
    logger.warn("Workspace migration written, but VS Code still shows the previous root; offering a reload.");
    const reload = "Reload Window";
    const choice = await vscode.window.showInformationMessage(
        "ALDC updated the workspace file, but VS Code has not applied it yet. Reload the window to show the new .external root.", reload);
    if (choice === reload) {
        await vscode.commands.executeCommand("workbench.action.reloadWindow");
    }
}

async function reconcileBcqualityCore(repositoryRoot: string, bcqualityRoot: string, logger: Logger, options?: ReconcileOptions): Promise<void> {
    const resolution = await resolveBcquality();
    const linkPath = path.join(repositoryRoot, ".external", "bcquality");

    if (resolution.enabled === false) {
        // A kill-switch must never strand infrastructure: this runs regardless of the opt-out setting below.
        logger.info("BCQuality is disabled in aldc.yaml; removing any existing link.");
        await removeBcqualityLink(linkPath, logger);
        return;
    }

    if (!autoReconcileBcquality()) {
        // The opt-out gates every write: workspace file, Global setting and link.
        logger.info("BCQuality reconciliation is switched off (bcquality.autoReconcile); leaving the workspace unchanged.");
        return;
    }
    // Runs in every mount mode and without a resolved clone: the constant entry depends on neither (Q-9).
    try {
        if (await migrateWorkspaceFile(repositoryRoot, logger)) {
            void checkMigrationApplied(logger, options?.staleCheckDelayMs ?? defaultStaleCheckDelayMs).catch(() => undefined);
        }
    } catch (error) {
        logger.warn(`Workspace migration failed: ${(error as Error).message}`);
    }
    // The env var and the link must not be two independently resolved answers: the caller's value
    // was resolved earlier and can already be stale by now.
    const home = resolution.verified && resolution.root ? resolution.root : bcqualityRoot;
    if (home) {
        await updateBcqualityHomeGlobalSetting(home);
    }

    if (externalMount() !== "junction") {
        // virtual/none: a junction left behind by an earlier mode is removed, never its target.
        await removeBcqualityLinkSafely(linkPath, logger);
        return;
    }
    if (!resolution.verified || !resolution.root) {
        // No verified clone yet (the default for a new project): never link to nothing.
        logger.info("BCQuality did not resolve to a verified clone; no link created.");
        return;
    }
    await createBcqualityLink(linkPath, resolution.root, logger);
}

async function removeBcqualityLinkSafely(linkPath: string, logger: Logger): Promise<void> {
    try {
        await removeBcqualityLink(linkPath, logger);
    } catch (error) {
        logger.warn(`BCQuality link could not be removed (${(error as Error).message}). Remove it with: cmd /c rmdir "${linkPath}"`);
    }
}

// The junction used to be created only by a command. An init that writes the *.code-workspace makes
// VS Code reload the window, killing the extension host mid-run -- so on a first init the link was
// never reached (measured: HEKS Base, 2026-09-28). Ordering alone cannot fix that; the desired state
// has to be re-established on activation instead of being tied to one run surviving.
export async function reconcileBcqualityOnStartup(repositoryRoot: string, logger: Logger, onReconciled?: () => void): Promise<void> {
    const resolution = await resolveBcquality();
    if (!shouldReconcileOnStartup(resolution)) {
        return;
    }
    await reconcileBcquality(repositoryRoot, resolution.root ?? "", logger, onReconciled);
}

// Pure, so the gate is testable. The workspace migration needs no clone, so every project reconciles;
// the Global BCQUALITY_HOME and the junction still require a verified clone inside the reconcile.
export function shouldReconcileOnStartup(_resolution: Pick<BcqualityResolution, "enabled" | "verified" | "root">): boolean {
    return true;
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
// Exported for testing: since this now runs on every activation, "writes nothing when nothing changed"
// is a property that has to be provable, not assumed.
export async function updateBcqualityHomeGlobalSetting(bcqualityRoot: string): Promise<void> {
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
            // Now that this runs on every activation, an unconditional update would rewrite the Global
            // settings file in every window -- and two projects resolving differently would flap it.
            if (existingGlobal.BCQUALITY_HOME === bcqualityRoot) {
                continue;
            }
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
    if (currentTarget && samePath(currentTarget, target)) {
        logger.info(`BCQuality link already correct: ${linkPath} -> ${target}`);
        return;
    }
    if (currentTarget) {
        await removeBcqualityLink(linkPath, logger);
    }
    await fs.mkdir(path.dirname(linkPath), { recursive: true });
    try {
        await fs.symlink(target, linkPath, process.platform === "win32" ? "junction" : "dir");
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") {
            throw error;
        }
        logger.warn(`BCQuality link not created: ${linkPath} already exists but cannot be read (typical for a junction on a network drive). Junctions on network drives do not work (E-006 e2e-05). Remove it with: cmd /c rmdir "${linkPath}"`);
        return;
    }
    if (await isLinkReadable(linkPath)) {
        logger.info(`Linked BCQuality: ${linkPath} -> ${target}`);
    } else {
        logger.warn(`BCQuality link created but not readable: ${linkPath} -> ${target} (typical for a junction on a network drive). Junctions on network drives do not work (E-006 e2e-05).`);
    }
}

// Windows path comparison is case-insensitive: readlink() reports the drive letter as stored ("C:\"),
// while a resolved candidate may carry it lower-cased, and treating those as different paths makes a
// healthy link look wrong.
function samePath(left: string, right: string): boolean {
    const a = path.resolve(left);
    const b = path.resolve(right);
    return process.platform === "win32" ? a.toLocaleLowerCase() === b.toLocaleLowerCase() : a === b;
}

// Defence in depth for Fix A (resolve.ts already canonicalises verified candidates): even if a future
// resolver change reintroduces a link-as-root, no self-referential junction can be created here.
// The link's identity is its canonical PARENT plus its own name -- never realpath(linkPath), which for a
// healthy junction returns the target and would condemn every correct link as a self-reference.
async function targetResolvesToLink(target: string, linkPath: string): Promise<boolean> {
    if (samePath(target, linkPath)) {
        return true;
    }
    return samePath(await canonicalOrResolved(target), await canonicalLinkPath(linkPath));
}

// Canonicalising the parent normalises Windows 8.3 short names (os.tmpdir() can yield LOCAL_~1.KOE)
// without following the link itself.
async function canonicalLinkPath(linkPath: string): Promise<string> {
    return path.join(await canonicalOrResolved(path.dirname(linkPath)), path.basename(linkPath));
}

async function canonicalOrResolved(candidatePath: string): Promise<string> {
    try {
        return path.resolve((await fs.realpath(candidatePath)).replace(/^\\\\\?\\/, ""));
    } catch {
        return path.resolve(candidatePath);
    }
}

async function isLinkReadable(linkPath: string): Promise<boolean> {
    try {
        await fs.readdir(linkPath);
        return true;
    } catch {
        return false;
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
    try {
        if (process.platform === "win32") {
            await fs.rmdir(linkPath);
        } else {
            await fs.unlink(linkPath);
        }
    } catch (error) {
        logger.warn(`BCQuality link could not be removed (${(error as Error).message}). Remove it with: cmd /c rmdir "${linkPath}"`);
        return;
    }
    logger.info(`Removed BCQuality link: ${linkPath}`);
}