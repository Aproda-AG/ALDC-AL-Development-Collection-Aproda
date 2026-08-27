import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";

export type AldcRepositoryResolution =
    | { state: "configured"; repositoryRoot: string; configurationPath: string }
    | { state: "notInstalled"; repositoryRoots: string[] }
    | { state: "ambiguousRepository"; repositoryRoots: string[] };

export async function findGitRoot(start: string): Promise<string | undefined> {
    let current = path.resolve(start);
    while (true) {
        if (await pathExists(path.join(current, ".git"))) {
            return current;
        }
        const parent = path.dirname(current);
        if (parent === current) {
            return undefined;
        }
        current = parent;
    }
}

export async function resolveTargetRepo(): Promise<string | undefined> {
    const folders = vscode.workspace.workspaceFolders ?? [];
    const roots = new Map<string, string>();
    for (const folder of folders) {
        const root = await findGitRoot(folder.uri.fsPath);
        if (root) {
            roots.set(root.toLocaleLowerCase(), root);
        }
    }

    if (roots.size === 0) {
        if (folders.length === 1) {
            return folders[0].uri.fsPath;
        }
        const selected = await vscode.window.showQuickPick(folders.map((folder) => ({
            label: folder.name,
            detail: folder.uri.fsPath,
            value: folder.uri.fsPath
        })), { placeHolder: "Choose the workspace folder to initialize as a Git repository" });
        return selected?.value;
    }
    if (roots.size === 1) {
        return [...roots.values()][0];
    }

    const choices = [...roots.values()].map((root) => ({
        label: path.basename(root),
        detail: root,
        value: root
    }));
    const selected = await vscode.window.showQuickPick(choices, {
        placeHolder: "Choose the repository to initialize"
    });
    return selected?.value;
}

export async function resolveAldcRepository(): Promise<AldcRepositoryResolution> {
    const roots = new Map<string, string>();
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        const root = await findGitRoot(folder.uri.fsPath);
        if (root) {
            roots.set(root.toLocaleLowerCase(), root);
        }
    }

    const repositoryRoots = [...roots.values()];
    const configuredRepositories: string[] = [];
    for (const repositoryRoot of repositoryRoots) {
        if (await pathExists(path.join(repositoryRoot, "aldc.yaml"))) {
            configuredRepositories.push(repositoryRoot);
        }
    }

    if (configuredRepositories.length === 1) {
        const repositoryRoot = configuredRepositories[0];
        return {
            state: "configured",
            repositoryRoot,
            configurationPath: path.join(repositoryRoot, "aldc.yaml")
        };
    }
    if (configuredRepositories.length > 1) {
        return { state: "ambiguousRepository", repositoryRoots: configuredRepositories };
    }
    return { state: "notInstalled", repositoryRoots };
}

async function pathExists(candidate: string): Promise<boolean> {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}
