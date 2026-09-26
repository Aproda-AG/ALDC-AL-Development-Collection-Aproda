import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { bcqualityPath, devRoot, updateGlobal } from "../config";
import { directoryExists } from "../env/devRoot";
import { AldcRepositoryResolution, findGitRoot } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";
import { resolveBcquality } from "./resolve";

const repository = "https://github.com/Aproda-AG/BCQuality-Aproda.git";

export async function installOrUpdateBcquality(logger: Logger): Promise<string | undefined> {
    const target = await resolveBcqualityPath();
    if (!target) {
        return undefined;
    }
    const exists = await directoryExists(target);
    if (!await isSafeTarget(target, exists)) {
        void vscode.window.showErrorMessage("BCQuality must be a standalone repository outside other Git repositories.");
        return undefined;
    }
    if (!exists && !await confirmClone(target)) {
        logger.info(`BCQuality clone to ${target} cancelled by the user.`);
        return undefined;
    }

    try {
        await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "Installing or updating BCQuality" }, async () => {
            if (!exists) {
                await fs.mkdir(path.dirname(target), { recursive: true });
                await runGit(["clone", repository, target], logger);
            } else {
                await runGit(["pull", "--ff-only"], logger, target);
            }
        });
        await updateGlobal("bcquality.path", target);
        void vscode.window.showInformationMessage(`BCQuality is ready at ${target}.`);
        return target;
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.error(`BCQuality installation failed: ${message}`);
        const selection = await vscode.window.showErrorMessage(`BCQuality installation failed: ${message}`, "Show Log");
        if (selection === "Show Log") {
            logger.show();
        }
        return undefined;
    }
}

export async function resolveBcqualityPath(repository?: AldcRepositoryResolution): Promise<string | undefined> {
    const resolution = await resolveBcquality(repository);
    if (resolution.verified && resolution.root) {
        return resolution.root;
    }
    const configured = bcqualityPath();
    if (configured) {
        return path.resolve(configured);
    }
    if (!devRoot()) {
        void vscode.window.showErrorMessage("Configure a Developer Root before installing central BCQuality.");
        return undefined;
    }
    return path.join(devRoot(), "BCQuality-Aproda");
}

// Creating a clone is the one irreversible step here, and a convention-derived target is
// indistinguishable from an existing clone the resolver lost track of -- so it is never done silently.
// Updating an existing clone stays unprompted: --ff-only cannot destroy local work.
async function confirmClone(target: string): Promise<boolean> {
    const choice = await vscode.window.showWarningMessage(
        "No BCQuality clone was found.",
        {
            modal: true,
            detail: `Clone it to ${target}?\n\nIf a clone already exists elsewhere, cancel and point the Aproda ALDC setting "bcquality.path" at it instead.`
        },
        "Clone"
    );
    return choice === "Clone";
}

async function isSafeTarget(target: string, exists: boolean): Promise<boolean> {
    if (exists) {
        return (await findGitRoot(target)) === target;
    }
    return !await findGitRoot(path.dirname(target));
}

async function runGit(args: string[], logger: Logger, cwd?: string): Promise<void> {
    logger.info(`git ${args.join(" ")} (${cwd ?? "default"})`);
    const result = await run("git", args, { cwd, env: { GIT_TERMINAL_PROMPT: "0" } });
    if (result.stdout.trim()) {
        logger.info(result.stdout.trim());
    }
    if (result.stderr.trim()) {
        logger.info(result.stderr.trim());
    }
    if (result.code !== 0) {
        throw new Error(`Git command failed: git ${args.join(" ")}`);
    }
}