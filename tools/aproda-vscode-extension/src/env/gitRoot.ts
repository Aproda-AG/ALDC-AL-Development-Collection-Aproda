import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { defaultEntryPoint } from "../bcquality/aldcConfig";

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
        const onlyRoot = [...roots.values()][0];
        if (await isBcqualityClone(onlyRoot)) {
            void vscode.window.showErrorMessage(
                "The only open repository is a BCQuality knowledge clone, not an AL project. Open the project you want to initialize instead."
            );
            return undefined;
        }
        return onlyRoot;
    }

    // A BCQuality knowledge clone is often mounted as its own git repository alongside the actual project
    // (D-49); applying the toolkit into it instead is destructive, so exclude it before ever asking.
    const nonCloneCandidates: string[] = [];
    for (const root of roots.values()) {
        if (!await isBcqualityClone(root)) {
            nonCloneCandidates.push(root);
        }
    }
    if (nonCloneCandidates.length === 0) {
        // Every candidate is a clone: a picker here would offer only wrong answers. Refuse, as the single-root case does.
        void vscode.window.showErrorMessage(
            "Every open repository is a BCQuality knowledge clone, not an AL project. Open the project you want to initialize instead."
        );
        return undefined;
    }
    const candidates = nonCloneCandidates;
    if (candidates.length === 1) {
        return candidates[0];
    }

    // Otherwise prefer the repository that already declares aldc.yaml: it is unambiguously the ALDC project.
    const withConfig: string[] = [];
    for (const root of candidates) {
        if (await resolveConfigurationPath(root)) {
            withConfig.push(root);
        }
    }
    if (withConfig.length === 1) {
        return withConfig[0];
    }

    const finalists = withConfig.length > 1 ? withConfig : candidates;
    const choices = finalists.map((root) => ({
        label: path.basename(root),
        detail: root,
        value: root
    }));
    const selected = await vscode.window.showQuickPick(choices, {
        placeHolder: "Choose the repository to initialize"
    });
    return selected?.value;
}

// A candidate's own aldc.yaml (if any) says nothing about its identity -- only the fixed default
// marker location proves it is a BCQuality clone, so it must never be substituted by the candidate's config.
async function isBcqualityClone(root: string): Promise<boolean> {
    return pathExists(path.join(root, defaultEntryPoint));
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
    const configured: { repositoryRoot: string; configurationPath: string }[] = [];
    for (const repositoryRoot of repositoryRoots) {
        const configurationPath = await resolveConfigurationPath(repositoryRoot);
        if (configurationPath) {
            configured.push({ repositoryRoot, configurationPath });
        }
    }

    if (configured.length === 1) {
        return { state: "configured", ...configured[0] };
    }
    if (configured.length > 1) {
        return { state: "ambiguousRepository", repositoryRoots: configured.map((entry) => entry.repositoryRoot) };
    }
    return { state: "notInstalled", repositoryRoots };
}

// Repository resolution for an already-known root: the ambient variant derives the root from the open
// workspace folders, which is wrong whenever the caller was handed a specific repository to act on.
export async function resolveAldcRepositoryAt(repositoryRoot: string): Promise<AldcRepositoryResolution> {
    const configurationPath = await resolveConfigurationPath(repositoryRoot);
    return configurationPath
        ? { state: "configured", repositoryRoot, configurationPath }
        : { state: "notInstalled", repositoryRoots: [repositoryRoot] };
}

// aldc.yaml lives at <toolkitRoot>/aldc.yaml (T-33): .github/ in a consuming project,
// the repo root in the fork. Probe .github first, then the root (pre-T-33 layout).
export async function resolveConfigurationPath(repositoryRoot: string): Promise<string | undefined> {
    for (const relative of [path.join(".github", "aldc.yaml"), "aldc.yaml"]) {
        const candidate = path.join(repositoryRoot, relative);
        if (await pathExists(candidate)) {
            return candidate;
        }
    }
    return undefined;
}

async function pathExists(candidate: string): Promise<boolean> {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}
