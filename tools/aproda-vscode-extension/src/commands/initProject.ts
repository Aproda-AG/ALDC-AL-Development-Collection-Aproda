import * as vscode from "vscode";
import { findGitRoot, resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";
import { runBootstrap } from "../ps/bridge";
import { LayerSource } from "../source/layerSource";
import { asMessage } from "../setup/doctor";

export async function initializeProject(source: LayerSource, logger: Logger, preview: boolean): Promise<void> {
    const repoRoot = await resolveTargetRepo();
    if (!repoRoot) {
        return;
    }
    if (!await ensureGitRepository(repoRoot, preview, logger)) {
        return;
    }
    if (!preview && !await confirmGitHubChanges(repoRoot, logger)) {
        return;
    }

    try {
        const result = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: preview ? "Previewing Aproda ALDC changes" : "Initializing Aproda ALDC project",
            cancellable: false
        }, async (progress) => {
            progress.report({ message: "Preparing layer source" });
            const layer = await source.ensure();
            progress.report({ message: preview ? "Calculating changes" : "Applying layer" });
            return runBootstrap(repoRoot, layer.path, preview, logger);
        });
        if (preview) {
            await showPreviewResult(result.changes, logger);
        } else {
            void vscode.window.showInformationMessage("Aproda ALDC initialization completed.");
        }
    } catch (error) {
        const message = asMessage(error);
        logger.error(message);
        void vscode.window.showErrorMessage(`Aproda ALDC ${preview ? "preview" : "initialization"} failed: ${message}`, "Show Log").then((selection) => {
            if (selection === "Show Log") {
                logger.show();
            }
        });
    }
}

async function showPreviewResult(changes: number | undefined, logger: Logger): Promise<void> {
    if (changes === 0) {
        void vscode.window.showInformationMessage("Aproda ALDC is up to date.");
        return;
    }
    const message = changes === undefined
        ? "Aproda ALDC preview completed. Review the output for planned changes."
        : `Aproda ALDC found ${changes} change${changes === 1 ? "" : "s"}.`;
    const selection = await vscode.window.showInformationMessage(message, "Show Log", "Update");
    if (selection === "Show Log") {
        logger.show();
    }
    if (selection === "Update") {
        void vscode.commands.executeCommand("aprodaAldc.initProject");
    }
}

async function ensureGitRepository(repoRoot: string, preview: boolean, logger: Logger): Promise<boolean> {
    if (await findGitRoot(repoRoot) === repoRoot) {
        return true;
    }
    if (preview) {
        void vscode.window.showErrorMessage("Preview requires the current workspace to be a Git repository.");
        return false;
    }

    const choice = await vscode.window.showWarningMessage(
        "The selected workspace is not a Git repository. Aproda ALDC requires a repository root.",
        "Initialize Git",
        "Cancel"
    );
    if (choice !== "Initialize Git") {
        return false;
    }
    const result = await run("git", ["init"], { cwd: repoRoot });
    if (result.code === 0) {
        logger.info(`Initialized Git repository: ${repoRoot}`);
        return true;
    }
    logger.error(result.stderr || result.stdout);
    void vscode.window.showErrorMessage("Git initialization failed. See Aproda ALDC output for details.");
    return false;
}

async function confirmGitHubChanges(repoRoot: string, logger: Logger): Promise<boolean> {
    const result = await run("git", ["status", "--porcelain", "--", ".github"], { cwd: repoRoot });
    if (result.code !== 0 || !result.stdout.trim()) {
        return true;
    }
    logger.info(`Uncommitted .github changes before initialization:\n${result.stdout.trim()}`);
    const choice = await vscode.window.showWarningMessage(
        "This project has uncommitted changes under .github. Initialization can overwrite Aproda ALDC files.",
        "Continue",
        "Cancel"
    );
    return choice === "Continue";
}
