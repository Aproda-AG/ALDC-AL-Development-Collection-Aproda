import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { bcqualityPath, devRoot, updateGlobal } from "../config";
import { directoryExists } from "../env/devRoot";
import { findGitRoot } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";

const repository = "https://github.com/Aproda-AG/BCQuality-Aproda.git";

export async function installOrUpdateBcquality(logger: Logger): Promise<string | undefined> {
    const target = await resolveBcqualityPath();
    if (!target) {
        return undefined;
    }
    if (!await isSafeTarget(target)) {
        void vscode.window.showErrorMessage("BCQuality must be a standalone repository outside other Git repositories.");
        return undefined;
    }

    try {
        await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "Installing or updating BCQuality" }, async () => {
            if (!await directoryExists(target)) {
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

export async function resolveBcqualityPath(): Promise<string | undefined> {
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

async function isSafeTarget(target: string): Promise<boolean> {
    if (await directoryExists(target)) {
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