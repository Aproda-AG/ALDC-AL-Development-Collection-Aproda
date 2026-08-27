import * as vscode from "vscode";
import { resetGlobalSettings } from "../config";
import { Logger } from "../log";
import { LayerSource } from "../source/layerSource";
import { offerInitialSetup, resetSetupState } from "../setup/wizard";
import { resetUpdateCheckState } from "../startup/check";
import { resetRepositoryInitializationState } from "../startup/repositoryInitialization";
import { resetExtensionUpdateCheckState } from "./extensionUpdate";

export async function resetLocalData(
    context: vscode.ExtensionContext,
    layerSource: LayerSource,
    logger: Logger,
    waitForStartupCheck: () => Promise<void> | undefined
): Promise<void> {
    const confirmation = await vscode.window.showWarningMessage(
        "Reset Aproda ALDC local data? This deletes the managed cache, global Aproda ALDC settings, and update-check state. Project files and local forks are not changed.",
        { modal: true },
        "Reset Local Data"
    );
    if (confirmation !== "Reset Local Data") {
        return;
    }

    try {
        await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: "Resetting Aproda ALDC local data" },
            async () => {
                await waitForStartupCheck();
                await layerSource.clearCache();
                await resetGlobalSettings();
                await resetUpdateCheckState(context);
                await resetExtensionUpdateCheckState(context);
                await resetRepositoryInitializationState(context);
                await resetSetupState(context);
            }
        );
        logger.info("Aproda ALDC local cache, global settings, and update-check state were reset.");
        void vscode.window.showInformationMessage("Aproda ALDC local data was reset. Project files and local forks were not changed.");
        void offerInitialSetup(context);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.error(`Could not reset Aproda ALDC local data: ${message}`);
        const selection = await vscode.window.showErrorMessage(`Aproda ALDC local data reset failed: ${message}`, "Show Log");
        if (selection === "Show Log") {
            logger.show();
        }
    }
}