import * as vscode from "vscode";

// Walkthrough step descriptions render fenced code blocks without a copy button, so the
// setup commands must be copied via a registered command instead of manual selection.
const ADO_CLI_SETUP_COMMANDS = [
    "az extension add --name azure-devops",
    "az login --tenant 8ad57af3-4ca5-4c66-bc7d-a52dd71dc7c9 --subscription bdcf3613-1ee6-4c3c-9caf-962112b8a6aa",
].join("\n");

export async function copyAdoCliSetupCommand(): Promise<void> {
    await vscode.env.clipboard.writeText(ADO_CLI_SETUP_COMMANDS);
    void vscode.window.showInformationMessage("Azure CLI setup commands copied to clipboard.");
}
