import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { initializeProject } from "../commands/initProject";
import { findGitRoot } from "../env/gitRoot";
import { Logger } from "../log";
import { LayerSource } from "../source/layerSource";

const dismissedRepositoriesKey = "dismissedRepositoryInitialization";

export async function resetRepositoryInitializationState(context: vscode.ExtensionContext): Promise<void> {
    await context.globalState.update(dismissedRepositoriesKey, undefined);
}

export async function offerRepositoryInitialization(context: vscode.ExtensionContext, logger: Logger, layerSource: LayerSource): Promise<void> {
    const repositories = await findUninitializedAlRepositories();
    if (repositories.length !== 1 || isDismissed(context, repositories[0])) {
        return;
    }

    const repositoryRoot = repositories[0];
    const selection = await vscode.window.showInformationMessage(
        "This AL project is not initialized with Aproda ALDC.",
        "Initialize ALDC",
        "Not now",
        "Don't ask again for this repository"
    );
    if (selection === "Initialize ALDC") {
        await initializeProject(layerSource, logger, false, repositoryRoot);
    }
    if (selection === "Don't ask again for this repository") {
        await dismissRepository(context, repositoryRoot);
    }
}

export async function hasInitializedAlProject(): Promise<boolean> {
    const repositories = await findAlRepositories();
    return repositories.some((repositoryRoot) => fs.existsSync(path.join(repositoryRoot, "aldc.yaml")));
}

async function findUninitializedAlRepositories(): Promise<string[]> {
    const repositories = await findAlRepositories();
    return repositories.filter((repositoryRoot) => !fs.existsSync(path.join(repositoryRoot, "aldc.yaml")));
}

async function findAlRepositories(): Promise<string[]> {
    const repositories = new Map<string, string>();
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        if (!fs.existsSync(path.join(folder.uri.fsPath, "app.json"))) {
            continue;
        }
        const repositoryRoot = await findGitRoot(folder.uri.fsPath) ?? folder.uri.fsPath;
        repositories.set(repositoryRoot.toLocaleLowerCase(), repositoryRoot);
    }
    return [...repositories.values()];
}

function isDismissed(context: vscode.ExtensionContext, repositoryRoot: string): boolean {
    return context.globalState.get<string[]>(dismissedRepositoriesKey, []).includes(repositoryKey(repositoryRoot));
}

async function dismissRepository(context: vscode.ExtensionContext, repositoryRoot: string): Promise<void> {
    const dismissed = context.globalState.get<string[]>(dismissedRepositoriesKey, []);
    const key = repositoryKey(repositoryRoot);
    if (!dismissed.includes(key)) {
        await context.globalState.update(dismissedRepositoriesKey, [...dismissed, key]);
    }
}

function repositoryKey(repositoryRoot: string): string {
    return path.resolve(repositoryRoot).toLocaleLowerCase();
}