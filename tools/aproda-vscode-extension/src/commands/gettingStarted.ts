import * as vscode from "vscode";
import { gettingStartedUrl } from "../config";

const walkthroughId = "aprodaag.aproda-aldc#aprodaAldc.gettingStarted";

export async function openGettingStarted(): Promise<void> {
    const url = gettingStartedUrl();
    if (!url) {
        void vscode.window.showErrorMessage("Aproda ALDC onboarding guide URL is not configured.");
        return;
    }
    try {
        await vscode.env.openExternal(vscode.Uri.parse(url));
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        void vscode.window.showErrorMessage(`Could not open the Aproda ALDC onboarding guide: ${message}`);
    }
}

export async function openWalkthrough(): Promise<void> {
    await vscode.commands.executeCommand("workbench.action.openWalkthrough", walkthroughId);
}