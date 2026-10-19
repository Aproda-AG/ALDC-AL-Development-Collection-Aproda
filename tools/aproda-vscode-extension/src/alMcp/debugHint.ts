import * as path from "path";
import * as vscode from "vscode";
import { resolveAldcRepository } from "../env/gitRoot";
import { Logger } from "../log";
import { getLaunchConfigurations, getLocalSelection } from "./localSelection";
import { applyTargetSelection, selectAlTarget } from "./selectTarget";

// Spec §4.8 / Q-11: an AL debug session started with another launch configuration never switches the target
// silently. One notification per configuration name and window.
export async function handleDebugSession(session: vscode.DebugSession, notifiedNames: Set<string>, logger: Logger): Promise<void> {
    if (session.type !== "al") {
        return;
    }
    const name = (session.configuration as { name?: unknown } | undefined)?.name;
    if (typeof name !== "string" || !name) {
        return;
    }
    const resolution = await resolveAldcRepository();
    if (resolution.state !== "configured") {
        return;
    }
    const selection = getLocalSelection(resolution.repositoryRoot);
    if (!selection.target || selection.target.launchConfig === name || notifiedNames.has(name)) {
        return;
    }
    notifiedNames.add(name);

    const choice = await vscode.window.showInformationMessage(`Switch ALDC target to ${name}?`, "Switch", "Keep");
    if (choice !== "Switch") {
        return;
    }
    const candidates = getLaunchConfigurations(resolution.repositoryRoot).filter((candidate) => candidate.name === name);
    const sessionFolder = session.workspaceFolder?.uri.fsPath;
    const sameFolder = sessionFolder
        ? candidates.filter((candidate) => path.resolve(resolution.repositoryRoot, candidate.launchProject).toLowerCase() === path.resolve(sessionFolder).toLowerCase())
        : [];
    const unique = sameFolder.length === 1 ? sameFolder : candidates.length === 1 ? candidates : [];
    if (unique.length === 1) {
        const [candidate] = unique;
        if (candidate.issues.length > 0) {
            void vscode.window.showWarningMessage(`'${name}' is blocked (${candidate.issues.map((issue) => issue.code).join(", ")}); the ALDC target was not changed.`);
            return;
        }
        await applyTargetSelection(resolution.repositoryRoot, candidate.launchProject, candidate.name, logger);
        return;
    }
    if (candidates.length === 0) {
        void vscode.window.showWarningMessage(`No launch.json configuration named '${name}' with a server was found; the ALDC target was not changed.`);
        return;
    }
    await selectAlTarget(logger);
}

export function registerDebugHint(context: vscode.ExtensionContext, logger: Logger): void {
    const notifiedNames = new Set<string>();
    context.subscriptions.push(vscode.debug.onDidStartDebugSession((session) => {
        void handleDebugSession(session, notifiedNames, logger).catch((error) => logger.error(`AL debug hint failed: ${error instanceof Error ? error.message : String(error)}`));
    }));
}
