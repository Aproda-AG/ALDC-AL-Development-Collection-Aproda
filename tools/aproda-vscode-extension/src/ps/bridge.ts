import * as path from "path";
import { pwshPath } from "../config";
import { Logger } from "../log";
import { run } from "../process";

export interface BootstrapResult {
    readonly changes?: number;
    readonly applied?: number;
}

export type MigrationStatus = "current" | "pending" | "unknown";

export interface MigrationPreflight {
    readonly status: MigrationStatus;
    readonly actions: readonly string[];
    readonly manual: readonly string[];
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
    return { changes: summary ? Number(summary[1]) : undefined, applied: parseAppliedCount(result.stdout) };
}

// The layout migration is the one part of an init that is one-way, so it is the only part worth
// interrupting for. Asking the migration itself keeps a single source of truth -- re-deriving
// "is a migration due?" in TypeScript would be a second enumeration drifting away from the first (B-43).
export async function runMigrationPreflight(projectRoot: string, forkPath: string, logger: Logger): Promise<MigrationPreflight> {
    const syncDir = path.join(forkPath, "tools", "aproda-sync");
    const scriptPath = path.join(syncDir, "Migrate-AprodaProjectLayout.ps1");
    const command = [
        "[Console]::OutputEncoding=[Text.Encoding]::UTF8",
        `$env:APRODA_SYNC_SCRIPTDIR=${psQuote(syncDir)}`,
        `& ([ScriptBlock]::Create((Get-Content -LiteralPath ${psQuote(scriptPath)} -Raw))) -ProjectRoot ${psQuote(projectRoot)} -WhatIf`
    ].join("; ");

    const result = await run(pwshPath(), ["-NoProfile", "-NonInteractive", "-Command", command], { env: { PYTHONIOENCODING: "utf-8" } });
    if (result.code !== 0) {
        logger.info(`Migration preflight could not run (exit code ${result.code}): ${result.stderr.trim() || result.stdout.trim()}`);
        return { status: "unknown", actions: [], manual: [] };
    }
    const preflight = parseMigrationPreflight(result.stdout);
    logger.info(`Migration preflight: ${preflight.status}${preflight.actions.length ? ` — ${preflight.actions.join("; ")}` : ""}`);
    for (const note of preflight.manual) {
        logger.info(`Migration preflight [manual]: ${note}`);
    }
    return preflight;
}

// Only `[migrated]` may interrupt: those are the one-way writes. Every `[manual]` case the migration
// can emit is either "run a pull first" -- which is exactly what this run is about to do -- or "left
// untouched"; blocking on them would reintroduce the false alarm this confirmation replaced (B-44).
export function parseMigrationPreflight(stdout: string): MigrationPreflight {
    const actions = [...stdout.matchAll(/^Init 5: \[migrated\]\s+(.+?)\s*$/gm)].map((match) => match[1]);
    const manual = [...stdout.matchAll(/^Init 5: \[manual\]\s+(.+?)\s*$/gm)].map((match) => match[1]);
    if (actions.length > 0) {
        return { status: "pending", actions, manual };
    }
    if (manual.length > 0 || /^Init 5: project layout already current/m.test(stdout)) {
        return { status: "current", actions: [], manual };
    }
    // Neither shape recognised: the script changed, or it never got that far. Saying "current" here
    // would be a check reporting success without having determined anything (B-6).
    return { status: "unknown", actions: [], manual: [] };
}

export function parseAppliedCount(stdout: string): number | undefined {
    const summary = /Done — (\d+) file\(s\) copied \+ (\d+) dual-variant/.exec(stdout);
    return summary ? Number(summary[1]) + Number(summary[2]) : undefined;
}

function psQuote(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
}
