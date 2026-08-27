import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { run } from "../process";

export async function validateInstallation(logger: Logger): Promise<void> {
    const repositoryRoot = await resolveTargetRepo();
    if (!repositoryRoot) {
        return;
    }
    const validatorRoot = path.join(repositoryRoot, ".github", "tools", "aldc-validate");
    const validator = path.join(validatorRoot, "index.js");
    if (!await pathExists(validator)) {
        void vscode.window.showErrorMessage("Aproda ALDC validator was not found. Apply the toolkit to this project first.");
        return;
    }

    try {
        const result = await vscode.window.withProgress(
            { location: vscode.ProgressLocation.Notification, title: "Validating Aproda ALDC installation" },
            async (progress) => {
                if (!await pathExists(path.join(validatorRoot, "node_modules", "js-yaml"))) {
                    progress.report({ message: "Installing validator dependencies" });
                    const install = await run("npm", ["install", "--omit=dev", "--no-package-lock"], { cwd: validatorRoot });
                    logResult(logger, install.stdout, install.stderr);
                    if (install.code !== 0) {
                        throw new Error("Could not install ALDC validator dependencies.");
                    }
                }
                progress.report({ message: "Running validation" });
                return run("node", [validator, "--config", "aldc.yaml"], { cwd: repositoryRoot });
            }
        );
        logResult(logger, result.stdout, result.stderr);
        await showResult(result, logger);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.error(`ALDC validation failed to run: ${message}`);
        const selection = await vscode.window.showErrorMessage(`Aproda ALDC validation failed: ${message}`, "Show Log");
        if (selection === "Show Log") {
            logger.show();
        }
    }
}

async function showResult(result: { code: number; stdout: string; stderr: string }, logger: Logger): Promise<void> {
    const warnings = Number(/COMPLIANT \((\d+) warning\(s\)\)/.exec(result.stdout)?.[1] ?? 0);
    const message = result.code === 0
        ? warnings === 0 ? "Aproda ALDC installation is valid." : `Aproda ALDC installation is valid with ${warnings} warning${warnings === 1 ? "" : "s"}.`
        : "Aproda ALDC validation found errors.";
    const selection = result.code === 0
        ? await vscode.window.showInformationMessage(message, "Show Log")
        : await vscode.window.showWarningMessage(message, "Show Log");
    if (selection === "Show Log") {
        logger.show();
    }
}

function logResult(logger: Logger, stdout: string, stderr: string): void {
    for (const output of [stdout, stderr]) {
        if (output.trim()) {
            logger.info(output.trim());
        }
    }
}

async function pathExists(candidate: string): Promise<boolean> {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}