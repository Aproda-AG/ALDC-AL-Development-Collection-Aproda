import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { applyEdits, modify, parse } from "jsonc-parser";
import { autoFixBcqualityWorkspacePath, setBcqualityEnvInWorkspace } from "../config";
import { Logger } from "../log";

type WorkspaceFolder = { name?: string; path?: string };

export async function reconcileBcqualityWorkspace(repositoryRoot: string, bcqualityRoot: string, logger: Logger): Promise<void> {
    if (!autoFixBcqualityWorkspacePath()) {
        return;
    }
    const desiredPath = path.relative(repositoryRoot, bcqualityRoot).replace(/\\/g, "/");
    const entries = await fs.readdir(repositoryRoot, { withFileTypes: true });
    for (const entry of entries.filter((entry) => entry.isFile() && entry.name.endsWith(".code-workspace"))) {
        const workspacePath = path.join(repositoryRoot, entry.name);
        if (vscode.workspace.textDocuments.some((document) => document.uri.fsPath === workspacePath && document.isDirty)) {
            logger.info(`Skipped BCQuality reconciliation for dirty workspace file: ${entry.name}`);
            continue;
        }
        await reconcileFile(workspacePath, desiredPath, bcqualityRoot, logger);
    }
}

async function reconcileFile(workspacePath: string, desiredPath: string, bcqualityRoot: string, logger: Logger): Promise<void> {
    const source = await fs.readFile(workspacePath, "utf8");
    const document = parse(source) as { folders?: WorkspaceFolder[] } | undefined;
    if (!document || typeof document !== "object") {
        logger.error(`Could not parse workspace file: ${workspacePath}`);
        return;
    }
    const folders = Array.isArray(document.folders) ? document.folders : [];
    const index = folders.findIndex((folder) => /BCQuality-Aproda/i.test(folder.path ?? ""));
    let updated = applyModification(source, ["folders"], folders);
    updated = applyModification(updated, index >= 0 ? ["folders", index, "path"] : ["folders", folders.length], index >= 0 ? desiredPath : { name: "BCQuality (Aproda ALDC)", path: desiredPath });
    if (setBcqualityEnvInWorkspace()) {
        updated = applyModification(updated, ["settings", "terminal.integrated.env.windows", "BCQUALITY_HOME"], bcqualityRoot);
    }
    updated = applyModification(updated, ["settings", "files.watcherExclude", desiredPath], true);
    updated = applyModification(updated, ["settings", "search.exclude", desiredPath], true);
    if (updated !== source) {
        await fs.writeFile(workspacePath, updated, "utf8");
        logger.info(`Reconciled BCQuality workspace root: ${workspacePath}`);
    }
}

function applyModification(source: string, path: (string | number)[], value: unknown): string {
    return applyEdits(source, modify(source, path, value, { formattingOptions: { insertSpaces: true, tabSize: 2 } }));
}