import * as vscode from "vscode";
import { Logger } from "../log";

export function openGitAuthenticationTerminal(repository: string, logger: Logger): void {
    const terminal = vscode.window.createTerminal({ name: "Aproda ALDC: Sign In to GitHub" });
    const command = `git ls-remote --tags ${psQuote(repository)}`;
    terminal.show(true);
    terminal.sendText(`pwsh -NoProfile -Command ${psQuote(command)}`, true);
    logger.info("Opened an interactive terminal for GitHub authentication.");
}

function psQuote(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
}