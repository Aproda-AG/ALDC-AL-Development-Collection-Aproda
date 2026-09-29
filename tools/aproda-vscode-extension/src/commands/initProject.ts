import * as vscode from "vscode";
import { findGitRoot, resolveAldcRepositoryAt, resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";
import { MigrationPreflight, runBootstrap, runMigrationPreflight } from "../ps/bridge";
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

    let layer: SourceStatus | undefined;
    try {
        // Captured before the bootstrap: it unmounts the pre-migration BCQuality root, after which an
        // existing clone is momentarily unresolvable and would be mistaken for a first-time install.
        // Trusted afterwards without re-probing because it was already verified, and no migration
        // variant relocates an already-verified clone.
        const knownBcquality = preview ? undefined : await resolveBcquality(await resolveAldcRepositoryAt(repoRoot));
        if (preview) {
            const result = await vscode.window.withProgress({
                location: vscode.ProgressLocation.Notification,
                title: "Previewing Aproda ALDC changes",
                cancellable: false
            }, async (progress) => {
                progress.report({ message: "Preparing toolkit source" });
                layer = await source.ensure();
                logger.info(`Applying toolkit from ${describeAppliedSource(layer)}.`);
                progress.report({ message: "Calculating changes" });
                return runBootstrap(repoRoot, layer.path, true, logger);
            });
            await showPreviewResult(result.changes, logger);
            return;
        }

        const preflight = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "Initializing Aproda ALDC project",
            cancellable: false
        }, async (progress) => {
            progress.report({ message: "Preparing toolkit source" });
            layer = await source.ensure();
            logger.info(`Applying toolkit from ${describeAppliedSource(layer)}.`);
            progress.report({ message: "Checking the project layout" });
            return runMigrationPreflight(repoRoot, layer.path, logger);
        });
        if (!await confirmMigration(preflight, logger)) {
            return;
        }
        const result = await vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: "Initializing Aproda ALDC project",
            cancellable: false
        }, async (progress) => {
            progress.report({ message: "Applying toolkit" });
            return runBootstrap(repoRoot, layer!.path, false, logger);
        });
        // The fallback must probe fresh: the bootstrap writes aldc.yaml itself, so a first init only
        // has a declared BCQuality home once it has run.
        const bcqualityRoot = knownBcquality?.verified && knownBcquality.root
            ? knownBcquality.root
            : await resolveBcqualityPath(await resolveAldcRepositoryAt(repoRoot));
        if (bcqualityRoot) {
            await reconcileBcquality(repoRoot, bcqualityRoot, logger);
        } else {
            logger.info("BCQuality did not resolve; skipping reconciliation.");
        }
        void vscode.window.showInformationMessage(describeInitResult(result.applied, describeAppliedSource(layer!)));
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

export interface InitConfirmation {
    readonly message: string;
    readonly actions: readonly string[];
}

// The predecessor asked git for uncommitted changes under .github and then asked the user on *every*
// run. Measured against a real project, that gate was inverted: layer files are git-ignored and so
// invisible to git status, while the paths it did see are outside the syncer's allowlist and can never
// be overwritten (B-44). A prompt that fires every time is clicked through by reflex, so only the two
// things worth stopping for remain: a one-way layout migration, and not knowing.
export function buildMigrationConfirmation(preflight: MigrationPreflight): InitConfirmation | undefined {
    if (preflight.status === "current") {
        return undefined;
    }
    if (preflight.status === "unknown") {
        return {
            message: "Aproda ALDC could not determine whether this project needs a one-way layout migration. Continue anyway?",
            actions: ["Continue", "Show Log", "Cancel"]
        };
    }
    return {
        message: `Aproda ALDC will migrate this project's layout — this is one-way: ${preflight.actions.join(" ")}`,
        actions: ["Continue", "Show Log", "Cancel"]
    };
}

export function describeInitResult(applied: number | undefined, source: string): string {
    return applied === undefined
        ? `Aproda ALDC initialization completed using ${source}.`
        : `Aproda ALDC updated ${applied} file${applied === 1 ? "" : "s"} using ${source}.`;
}

async function confirmMigration(preflight: MigrationPreflight, logger: Logger): Promise<boolean> {
    const confirmation = buildMigrationConfirmation(preflight);
    if (!confirmation) {
        return true;
    }
    const choice = await vscode.window.showWarningMessage(confirmation.message, ...confirmation.actions);
    if (choice === "Show Log") {
        logger.show();
        return false;
    }
    return choice === "Continue";
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
