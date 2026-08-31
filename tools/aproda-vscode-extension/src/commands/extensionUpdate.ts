import * as vscode from "vscode";
import { Logger } from "../log";
import { findExtensionUpdate, installExtensionUpdate } from "../extensionUpdate/service";

const lastCheckKey = "lastExtensionUpdateCheck";
const skipKey = "skippedExtensionVersion";

export async function checkForExtensionUpdates(context: vscode.ExtensionContext, logger: Logger, manual: boolean): Promise<void> {
    try {
        const update = await findExtensionUpdate(logger);
        if (!update) {
            if (manual) {
                void vscode.window.showInformationMessage("Aproda ALDC extension is up to date.");
            }
            return;
        }
        if (!manual && context.globalState.get<string>(skipKey) === update.available) {
            return;
        }

        const selection = await vscode.window.showInformationMessage(
            `Aproda ALDC extension update available: ${update.current} -> ${update.available}.`,
            "Update Extension",
            "Later",
            "Skip this version"
        );
        if (selection === "Update Extension") {
            await vscode.window.withProgress(
                { location: vscode.ProgressLocation.Notification, title: "Updating Aproda ALDC extension" },
                () => installExtensionUpdate(context, update, logger)
            );
            const reload = await vscode.window.showInformationMessage("Aproda ALDC extension update installed. Reload VS Code to use it.", "Reload Window");
            if (reload === "Reload Window") {
                await vscode.commands.executeCommand("workbench.action.reloadWindow");
            }
        }
        if (selection === "Skip this version") {
            await context.globalState.update(skipKey, update.available);
        }
    } catch (error) {
        logger.error(error instanceof Error ? error.message : String(error));
        const selection = await vscode.window.showErrorMessage("Aproda ALDC extension update failed. Sign in to GitHub, then retry.", "Sign In / Retry", "Show Log");
        if (selection === "Sign In / Retry") {
            // Uses VS Code's own GitHub auth (separate from Git Credential Manager) - force a fresh session, then retry.
            await vscode.authentication.getSession("github", ["repo"], { createIfNone: true, forceNewSession: true });
            await checkForExtensionUpdates(context, logger, manual);
        }
        if (selection === "Show Log") {
            logger.show();
        }
    } finally {
        await context.globalState.update(lastCheckKey, Date.now());
    }
}

export function shouldRunExtensionUpdateCheck(context: vscode.ExtensionContext, intervalHours: number): boolean {
    const lastCheck = context.globalState.get<number>(lastCheckKey, 0);
    return Date.now() - lastCheck >= intervalHours * 60 * 60 * 1000;
}

export async function resetExtensionUpdateCheckState(context: vscode.ExtensionContext): Promise<void> {
    await Promise.all([
        context.globalState.update(lastCheckKey, undefined),
        context.globalState.update(skipKey, undefined)
    ]);
}