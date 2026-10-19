import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { pwshPath } from "../config";
import { resolveAldcRepository } from "../env/gitRoot";
import { Logger } from "../log";
import { getLocalSelection } from "./localSelection";
import { psQuote } from "./psQuote";
import { selectAlTarget } from "./selectTarget";
import { resolveToolkitRoot } from "./toolkit";

// Same store as skill-aproda-fkh/scripts/FkhCredentialStore.ps1 (D-43): %LOCALAPPDATA%\AprodaFkh\credentials.
export function credentialStoreDirectory(localAppData: string | undefined = process.env.LOCALAPPDATA): string | undefined {
    return localAppData ? path.join(localAppData, "AprodaFkh", "credentials") : undefined;
}

// Identical to ConvertTo-FkhCredentialStoreFileName: every .NET invalid file-name char becomes "_".
export function credentialFileName(key: string): string {
    return `${key.replace(/[<>:"/\\|?*\x00-\x1F]/g, "_")}.cred.xml`;
}

// Presence by file existence only: the credential file is never read or decrypted here.
export function hasStoredCredential(key: string | null | undefined, localAppData?: string): boolean {
    const directory = credentialStoreDirectory(localAppData);
    if (!key || !directory) {
        return false;
    }
    try {
        return fs.statSync(path.join(directory, credentialFileName(key))).isFile();
    } catch {
        return false;
    }
}

// The password is typed into Get-Credential's prompt in this terminal only; it never passes through the extension.
export function buildStoreCredentialCommand(storeScriptPath: string, host: string): string {
    return [
        "$ErrorActionPreference = 'Stop'",
        `. ([ScriptBlock]::Create((Get-Content -LiteralPath ${psQuote(storeScriptPath)} -Raw)))`,
        `Save-FkhCredential -Key ${psQuote(host)} -Credential (Get-Credential -Message ${psQuote(`AL target ${host}`)})`,
        `Write-Host ${psQuote(`Credential stored for ${host}. You can close this terminal.`)}`
    ].join("; ");
}

export async function storeAlCredential(logger: Logger): Promise<void> {
    const resolution = await resolveAldcRepository();
    if (resolution.state !== "configured") {
        void vscode.window.showWarningMessage("No ALDC repository found for the open workspace; cannot store an AL credential.");
        return;
    }
    const selection = getLocalSelection(resolution.repositoryRoot);
    if (selection.state !== "configured" || !selection.resolvedLaunch?.credentialKey) {
        const choice = await vscode.window.showWarningMessage("No valid AL target is selected, so there is no host to store a credential for.", "Select target");
        if (choice === "Select target") {
            await selectAlTarget(logger);
        }
        return;
    }
    const resolved = selection.resolvedLaunch;
    if (resolved.authentication !== "UserPassword") {
        void vscode.window.showInformationMessage(`The selected AL target '${resolved.name}' uses ${resolved.authentication ?? "no"} authentication; no stored credential is needed.`);
        return;
    }
    const toolkitRoot = resolveToolkitRoot(resolution.repositoryRoot, resolution.configurationPath);
    const storeScript = toolkitRoot ? path.join(toolkitRoot, "skills", "skill-aproda-fkh", "scripts", "FkhCredentialStore.ps1") : undefined;
    if (!storeScript || !fs.existsSync(storeScript)) {
        logger.error("AL credential store script not found; apply the toolkit (skill-aproda-fkh) first.");
        void vscode.window.showErrorMessage("The Fkh credential store script is missing in this repository. Apply the toolkit to the project first.");
        return;
    }

    const host = resolved.credentialKey!;
    logger.info(`Opening the AL credential terminal for ${host}.`);
    const terminal = vscode.window.createTerminal({
        name: "Aproda ALDC: AL credential",
        shellPath: pwshPath(),
        shellArgs: ["-NoProfile", "-NoExit", "-Command", buildStoreCredentialCommand(storeScript, host)]
    });
    terminal.show(true);
}
