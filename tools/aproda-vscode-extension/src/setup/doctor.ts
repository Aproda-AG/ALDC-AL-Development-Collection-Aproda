import * as path from "path";
import * as vscode from "vscode";
import { channel, forkPath, repositoryUrl, sourceMode } from "../config";
import { Logger } from "../log";
import { run } from "../process";
import { LayerSource } from "../source/layerSource";

export async function runDoctor(context: vscode.ExtensionContext, logger: Logger, source: LayerSource): Promise<void> {
    logger.info("Starting environment diagnostics.");
    const checks: Array<[string, string]> = [
        ["Git", "git"],
        ["PowerShell", "pwsh"],
        ["Node.js", "node"]
    ];

    for (const [name, executable] of checks) {
        try {
            const result = await run(executable, ["--version"]);
            logger.info(`${name}: ${result.code === 0 ? result.stdout.trim() : result.stderr.trim()}`);
        } catch {
            logger.error(`${name}: not found on PATH.`);
        }
    }

    logger.info(`Source mode: ${sourceMode()}`);
    logger.info(`Repository URL: ${repositoryUrl()}`);
    if (sourceMode() === "localFork") {
        logger.info(`Local fork path: ${forkPath() || "not configured"}`);
    }
    logger.info(`Extension global storage: ${context.globalStorageUri.fsPath}`);
    logger.info(`Managed toolkit cache path: ${path.join(context.globalStorageUri.fsPath, "layer-cache", "fork")}`);
    logger.info(`Channel: ${channel()}`);

    try {
        const status = await source.describe();
        logger.info(`Toolkit source: ${status.message}`);
    } catch (error) {
        logger.error(`Toolkit source: ${asMessage(error)}`);
    }

    logger.show();
}

export function asMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
}
