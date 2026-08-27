import * as vscode from "vscode";
import { resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { repositoryUrl } from "../config";
import { openGitAuthenticationTerminal } from "../source/authenticate";
import { VersionService } from "../version/service";

const lastCheckKey = "lastLayerUpdateCheck";
const skipKey = "skippedLayerVersion";
const disabledKey = "layerUpdateChecksDisabled";

export async function checkForLayerUpdates(context: vscode.ExtensionContext, logger: Logger, manual: boolean): Promise<void> {
    if (!manual && context.workspaceState.get<boolean>(disabledKey)) {
        return;
    }
    const repoRoot = await resolveTargetRepo();
    if (!repoRoot) {
        return;
    }
    const service = new VersionService(logger);
    try {
        const result = await service.check(repoRoot);
        if (manual) {
            await showManualResult(result, logger);
            return;
        }
        await showStartupResult(context, result, logger);
    } catch (error) {
        logger.error(error instanceof Error ? error.message : String(error));
        if (manual) {
            void vscode.window.showErrorMessage("Aproda ALDC update check failed. Sign in to GitHub, then retry the check.", "Sign In / Retry", "Show Log").then((selection) => {
                if (selection === "Sign In / Retry") {
                    openGitAuthenticationTerminal(repositoryUrl(), logger);
                }
                if (selection === "Show Log") {
                    logger.show();
                }
            });
        }
    }
}

export function shouldRunStartupCheck(context: vscode.ExtensionContext, intervalHours: number): boolean {
    const lastCheck = context.globalState.get<number>(lastCheckKey, 0);
    return Date.now() - lastCheck >= intervalHours * 60 * 60 * 1000;
}

export async function markStartupCheckComplete(context: vscode.ExtensionContext): Promise<void> {
    await context.globalState.update(lastCheckKey, Date.now());
}

export async function resetUpdateCheckState(context: vscode.ExtensionContext): Promise<void> {
    await Promise.all([
        context.globalState.update(lastCheckKey, undefined),
        context.workspaceState.update(skipKey, undefined),
        context.workspaceState.update(disabledKey, undefined)
    ]);
}

async function showManualResult(result: Awaited<ReturnType<VersionService["check"]>>, logger: Logger): Promise<void> {
    if (result.status === "outdated") {
        await showUpdateActions(result.message, logger);
        return;
    }
    const selection = await vscode.window.showInformationMessage(result.message, "Show Log");
    if (selection === "Show Log") {
        logger.show();
    }
}

async function showStartupResult(context: vscode.ExtensionContext, result: Awaited<ReturnType<VersionService["check"]>>, logger: Logger): Promise<void> {
    if (result.status === "notInstalled") {
        const selection = await vscode.window.showInformationMessage(result.message, "Install", "Later", "Never for this project");
        if (selection === "Install") {
            void vscode.commands.executeCommand("aprodaAldc.initProject");
        }
        if (selection === "Never for this project") {
            await context.workspaceState.update(disabledKey, true);
        }
        return;
    }
    if (result.status !== "outdated" || context.workspaceState.get<string>(skipKey) === result.available) {
        return;
    }
    const selection = await vscode.window.showInformationMessage(result.message, "Update", "Preview Changes", "Later", "Skip this version");
    if (selection === "Update") {
        void vscode.commands.executeCommand("aprodaAldc.initProject");
    }
    if (selection === "Preview Changes") {
        void vscode.commands.executeCommand("aprodaAldc.previewChanges");
    }
    if (selection === "Skip this version" && result.available) {
        await context.workspaceState.update(skipKey, result.available);
    }
}

async function showUpdateActions(message: string, logger: Logger): Promise<void> {
    const selection = await vscode.window.showInformationMessage(message, "Update", "Preview Changes", "Show Log");
    if (selection === "Update") {
        void vscode.commands.executeCommand("aprodaAldc.initProject");
    }
    if (selection === "Preview Changes") {
        void vscode.commands.executeCommand("aprodaAldc.previewChanges");
    }
    if (selection === "Show Log") {
        logger.show();
    }
}
