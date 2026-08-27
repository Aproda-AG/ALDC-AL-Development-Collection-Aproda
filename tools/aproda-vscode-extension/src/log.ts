import * as vscode from "vscode";

export class Logger implements vscode.Disposable {
    private readonly channel = vscode.window.createOutputChannel("Aproda ALDC");

    info(message: string): void {
        this.channel.appendLine(`[${new Date().toISOString()}] ${message}`);
    }

    error(message: string): void {
        this.info(`ERROR: ${message}`);
    }

    show(): void {
        this.channel.show(true);
    }

    dispose(): void {
        this.channel.dispose();
    }
}
