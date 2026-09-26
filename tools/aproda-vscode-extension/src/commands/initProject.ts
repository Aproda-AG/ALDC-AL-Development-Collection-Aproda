import * as vscode from "vscode";
import { findGitRoot, resolveAldcRepositoryAt, resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";
import { runBootstrap } from "../ps/bridge";
import { LayerSource, SourceStatus } from "../source/layerSource";
import { asMessage } from "../setup/doctor";
import { resolveBcqualityPath } from "../bcquality/install";
import { resolveBcquality } from "../bcquality/resolve";
import { reconcileBcquality } from "../workspace/bcqualityRoot";

export async function initializeProject(source: LayerSource, logger: Logger, preview: boolean, targetRepositoryRoot?: string): Promise<void> {
    const repoRoot = targetRepositoryRoot ?? await resolveTargetRepo();
    if (!repoRoot) {
        return;
    }
    if (!await ensureGitRepository(repoRoot, preview, logger)) {
        return;
    }
    if (!preview && !await confirmGitHubChanges(repoRoot, logger)) {
        return;
    }

    let layer: SourceStatus | undefined;
    try {
        // Captured before the bootstrap: it unmounts the pre-migration BCQuality root, after which an
        // existing clone is momentarily unresolvable and would be mistaken for a first-time install.
        // Trusted afterwards without re-probing because it was already verified, and no migration
        // variant relocates an already-verified clone.
        const knownBcquality = preview ? undefined : await resolveBcquality(await resolveAldcRepositoryAt(repoRoot));
        const result = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: preview ? "Previewing Aproda ALDC changes" : "Initializing Aproda ALDC project",
            cancellable: false
        }, async (progress) => {
            progress.report({ message: "Preparing toolkit source" });
            layer = await source.ensure();
            logger.info(`Applying toolkit from ${describeAppliedSource(layer)}.`);
            progress.report({ message: preview ? "Calculating changes" : "Applying toolkit" });
            return runBootstrap(repoRoot, layer.path, preview, logger);
        });
        if (preview) {
            await showPreviewResult(result.changes, logger);
        } else {
            // The fallback must probe fresh: the bootstrap writes aldc.yaml itself, so a first init only
            // has a declared BCQuality home once it has run.
            const bcqualityRoot = knownBcquality?.verified && knownBcquality.root
                ? knownBcquality.root
                : await resolveBcqualityPath(await resolveAldcRepositoryAt(repoRoot));
            if (bcqualityRoot) {
                await reconcileBcquality(repoRoot, bcqualityRoot, logger);
            }
            void vscode.window.showInformationMessage(`Aproda ALDC initialization completed using ${describeAppliedSource(layer!)}.`);
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

// Surfaces which toolkit source was actually applied (managed cache vs. local fork): a mismatch here
// between belief and reality is otherwise invisible until every downstream symptom is misdiagnosed.
function describeAppliedSource(layer: SourceStatus): string {
    return layer.mode === "managed"
        ? `the managed toolkit cache${layer.reference ? ` (${layer.reference})` : ""}`
        : `the local fork at ${layer.path}`;
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
