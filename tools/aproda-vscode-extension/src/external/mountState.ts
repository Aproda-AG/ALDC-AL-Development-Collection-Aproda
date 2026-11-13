import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { parse } from "jsonc-parser";
import { externalScheme, externalWrapperFolder } from "./externalFileSystemProvider";

export type JunctionState = "absent" | "readable" | "unreadable";
export type WorkspaceRootForm = "uri" | "path" | "missing" | "noWorkspaceFile" | "unparseable";

export function junctionPath(repositoryRoot: string): string {
    return path.join(repositoryRoot, externalWrapperFolder, "bcquality");
}

// absent: nothing at .external/bcquality (or a real folder, which is not a link); readable/unreadable: a link
// (junction/symlink) whose target can / cannot be listed (a junction on a network drive typically cannot).
export async function junctionState(repositoryRoot: string): Promise<JunctionState> {
    const target = junctionPath(repositoryRoot);
    try {
        if (!(await fs.lstat(target)).isSymbolicLink()) {
            return "absent";
        }
    } catch {
        return "absent";
    }
    try {
        await fs.readdir(target);
        return "readable";
    } catch {
        return "unreadable";
    }
}

export async function workspaceRootForm(): Promise<WorkspaceRootForm> {
    const workspaceFile = vscode.workspace.workspaceFile;
    if (!workspaceFile || workspaceFile.scheme !== "file") {
        return "noWorkspaceFile";
    }
    let text: string;
    try {
        text = await fs.readFile(workspaceFile.fsPath, "utf8");
    } catch {
        return "noWorkspaceFile";
    }
    const errors: unknown[] = [];
    const document = parse(text, errors as never[], { allowTrailingComma: true }) as { folders?: unknown } | undefined;
    if (errors.length > 0 || !document || typeof document !== "object") {
        return "unparseable";
    }
    const folders = Array.isArray(document.folders) ? document.folders : [];
    let form: WorkspaceRootForm = "missing";
    for (const entry of folders) {
        if (!entry || typeof entry !== "object") {
            continue;
        }
        const record = entry as { name?: unknown; path?: unknown; uri?: unknown };
        if (typeof record.uri === "string" && record.uri.toLowerCase().startsWith(`${externalScheme}:`)) {
            return "uri";
        }
        const entryPath = typeof record.path === "string" ? record.path.replace(/\\/g, "/").replace(/\/+$/, "") : undefined;
        if (record.name === externalWrapperFolder || (entryPath !== undefined && path.posix.basename(entryPath) === externalWrapperFolder)) {
            form = "path";
        }
    }
    return form;
}
