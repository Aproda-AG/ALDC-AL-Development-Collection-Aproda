import * as vscode from "vscode";
import { gettingStartedUrl } from "../config";

export async function openGettingStarted(): Promise<void> {
    const url = gettingStartedUrl();
    if (!url) {
        void vscode.window.showErrorMessage("Aproda ALDC Getting Started URL is not configured.");
        return;
    }
    try {
        await vscode.env.openExternal(vscode.Uri.parse(url));
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        void vscode.window.showErrorMessage(`Could not open Aproda ALDC Getting Started: ${message}`);
    }
}