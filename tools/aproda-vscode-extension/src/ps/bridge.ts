import * as path from "path";
import { pwshPath } from "../config";
import { Logger } from "../log";
import { run } from "../process";

export interface BootstrapResult {
    readonly changes?: number;
}

export async function runBootstrap(projectRoot: string, forkPath: string, preview: boolean, logger: Logger): Promise<BootstrapResult> {
    const syncDir = path.join(forkPath, "tools", "aproda-sync");
    const scriptPath = path.join(syncDir, "Bootstrap-AprodaProject.ps1");
    const command = [
        "[Console]::OutputEncoding=[Text.Encoding]::UTF8",
        `$env:APRODA_SYNC_SCRIPTDIR=${psQuote(syncDir)}`,
        `& ([ScriptBlock]::Create((Get-Content -LiteralPath ${psQuote(scriptPath)} -Raw))) -ProjectRoot ${psQuote(projectRoot)} -ForkPath ${psQuote(forkPath)}${preview ? " -WhatIf" : ""}`
    ].join("; ");

    logger.info(`Running ${preview ? "preview" : "initialization"} for ${projectRoot}.`);
    const result = await run(pwshPath(), ["-NoProfile", "-NonInteractive", "-Command", command], { env: { PYTHONIOENCODING: "utf-8" } });
    if (result.stdout.trim()) {
        logger.info(result.stdout.trim());
    }
    if (result.stderr.trim()) {
        logger.info(result.stderr.trim());
    }
    if (result.code !== 0) {
        throw new Error(`PowerShell bootstrap failed with exit code ${result.code}.`);
    }
    const summary = /DRY-RUN complete — (\d+) change\(s\) would be applied\./.exec(result.stdout);
    return { changes: summary ? Number(summary[1]) : undefined };
}

function psQuote(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
}
