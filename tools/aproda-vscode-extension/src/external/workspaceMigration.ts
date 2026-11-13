import * as fs from "fs/promises";
import * as path from "path";
import { applyEdits, findNodeAtLocation, modify, parse, parseTree, Edit, FormattingOptions, Node, ParseError } from "jsonc-parser";
import * as vscode from "vscode";
import { Logger } from "../log";

export const externalConstantUri = "aldc-external:/";
const externalName = ".external";
const legacyNamePattern = /^bcquality(-aproda)?$/i;
const terminalEnvKeys = ["terminal.integrated.env.windows", "terminal.integrated.env.linux", "terminal.integrated.env.osx"];
const excludeKeys = ["search.exclude", "files.watcherExclude"];

export interface MigrationResult {
    readonly text: string;
    readonly changes: readonly string[];
    readonly parseFailed: boolean;
}

// Last path segment, separators and trailing slashes normalised.
function lastSegment(folderPath: string): string {
    const parts = folderPath.replace(/\\/g, "/").split("/").filter((part) => part.length > 0);
    return parts.length > 0 ? parts[parts.length - 1] : "";
}

function isExternalPath(folderPath: string): boolean {
    return path.posix.normalize(folderPath.replace(/\\/g, "/")).replace(/\/+$/, "") === externalName;
}

async function isLegacyClone(folderPath: string, workspaceDir: string): Promise<boolean> {
    if (legacyNamePattern.test(lastSegment(folderPath))) {
        return true;
    }
    const resolved = path.isAbsolute(folderPath) ? folderPath : path.resolve(workspaceDir, folderPath);
    try {
        await fs.access(path.join(resolved, "skills", "entry.md"));
        return true;
    } catch {
        return false;
    }
}

function detectFormatting(text: string): FormattingOptions {
    const eol = text.includes("\r\n") ? "\r\n" : "\n";
    const indent = /^([ \t]+)\S/m.exec(text)?.[1] ?? "  ";
    return indent.startsWith("\t") ? { insertSpaces: false, tabSize: 4, eol } : { insertSpaces: true, tabSize: indent.length, eol };
}

// Mirrors the style of the entry it replaces (inline stays inline).
function constantEntryText(original: Node, text: string): string {
    if (/[\r\n]/.test(text.slice(original.offset, original.offset + original.length))) {
        const lineStart = text.lastIndexOf("\n", original.offset) + 1;
        const eol = text.includes("\r\n") ? "\r\n" : "\n";
        const baseIndent = /^[ \t]*/.exec(text.slice(lineStart))?.[0] ?? "";
        const formatting = detectFormatting(text);
        const inner = formatting.insertSpaces ? " ".repeat(formatting.tabSize ?? 2) : "\t";
        return `{${eol}${baseIndent}${inner}"name": "${externalName}",${eol}${baseIndent}${inner}"uri": "${externalConstantUri}"${eol}${baseIndent}}`;
    }
    return `{ "name": "${externalName}", "uri": "${externalConstantUri}" }`;
}

function globNamesRoot(glob: string, removed: readonly { folderPath: string; name: string }[]): boolean {
    const normalized = glob.replace(/\\/g, "/").toLowerCase();
    return removed.some((root) => {
        const full = root.folderPath.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
        return (full.length > 0 && normalized.includes(full)) || (root.name.length > 0 && normalized.split("/").some((segment) => segment.replace(/[*{}]/g, "") === root.name.toLowerCase()));
    });
}

// Pure apart from existence probes of candidate legacy folders; comment-preserving.
export async function migrateWorkspaceText(original: string, workspaceDir: string): Promise<MigrationResult> {
    const errors: ParseError[] = [];
    const tree = parseTree(original, errors, { allowTrailingComma: true });
    if (!tree || errors.length > 0 || tree.type !== "object") {
        return { text: original, changes: [], parseFailed: true };
    }
    const foldersNode = findNodeAtLocation(tree, ["folders"]);
    const folders = foldersNode?.type === "array" ? foldersNode.children ?? [] : [];
    if (foldersNode && foldersNode.type !== "array") {
        return { text: original, changes: [], parseFailed: true };
    }

    const formatting = detectFormatting(original);
    const changes: string[] = [];
    const removedRoots: { folderPath: string; name: string }[] = [];
    type Plan = { readonly kind: "keep" | "remove" | "replace"; readonly reason?: string };
    const plans: Plan[] = [];
    let constantSeen = false;
    const hasConstant = folders.some((node) => findNodeAtLocation(node, ["uri"])?.value === externalConstantUri);
    let placed = false;

    for (const node of folders) {
        const uri = findNodeAtLocation(node, ["uri"])?.value;
        const folderPath = findNodeAtLocation(node, ["path"])?.value;
        const name = findNodeAtLocation(node, ["name"])?.value;
        if (uri === externalConstantUri) {
            if (constantSeen) {
                plans.push({ kind: "remove", reason: "removed duplicate aldc-external entry" });
            } else {
                constantSeen = true;
                placed = true;
                plans.push({ kind: "keep" });
            }
            continue;
        }
        const pathText = typeof folderPath === "string" ? folderPath : undefined;
        if (name === externalName || (pathText !== undefined && isExternalPath(pathText))) {
            if (hasConstant || placed) {
                plans.push({ kind: "remove", reason: `removed redundant ${externalName} root` });
            } else {
                placed = true;
                plans.push({ kind: "replace", reason: `replaced ${externalName} path root by ${externalConstantUri}` });
            }
            continue;
        }
        if (pathText !== undefined && await isLegacyClone(pathText, workspaceDir)) {
            removedRoots.push({ folderPath: pathText, name: lastSegment(pathText) });
            plans.push({ kind: "remove", reason: `removed legacy BCQuality root '${pathText}'` });
            continue;
        }
        plans.push({ kind: "keep" });
    }

    let text = original;
    // Descending, so earlier indexes stay valid.
    for (let index = folders.length - 1; index >= 0; index--) {
        const plan = plans[index];
        if (plan.kind === "keep") {
            continue;
        }
        changes.push(plan.reason!);
        if (plan.kind === "remove") {
            text = applyEdits(text, modify(text, ["folders", index], undefined, { formattingOptions: formatting }));
        } else {
            const current = findNodeAtLocation(parseTree(text, [], { allowTrailingComma: true })!, ["folders", index])!;
            const edit: Edit = { offset: current.offset, length: current.length, content: constantEntryText(current, text) };
            text = applyEdits(text, [edit]);
        }
    }
    if (!placed) {
        changes.push(`added ${externalConstantUri} root`);
        const entry = { name: externalName, uri: externalConstantUri };
        text = applyEdits(text, foldersNode
            ? modify(text, ["folders", -1], entry, { formattingOptions: formatting, isArrayInsertion: true })
            : modify(text, ["folders"], [entry], { formattingOptions: formatting }));
    }

    if (removedRoots.length > 0) {
        const settings = (parse(text, [], { allowTrailingComma: true }) as { settings?: Record<string, unknown> } | undefined)?.settings;
        if (settings && typeof settings === "object") {
            for (const key of excludeKeys) {
                const block = settings[key];
                if (!block || typeof block !== "object") {
                    continue;
                }
                for (const glob of Object.keys(block as Record<string, unknown>)) {
                    if (globNamesRoot(glob, removedRoots)) {
                        text = applyEdits(text, modify(text, ["settings", key, glob], undefined, { formattingOptions: formatting }));
                        changes.push(`removed ${key} glob '${glob}'`);
                    }
                }
            }
            for (const key of terminalEnvKeys) {
                const env = settings[key];
                if (env && typeof env === "object" && "BCQUALITY_HOME" in (env as Record<string, unknown>)) {
                    const onlyKey = Object.keys(env as Record<string, unknown>).length === 1;
                    text = applyEdits(text, modify(text, onlyKey ? ["settings", key] : ["settings", key, "BCQUALITY_HOME"], undefined, { formattingOptions: formatting }));
                    changes.push(`removed BCQUALITY_HOME from ${key}`);
                }
            }
        }
    }
    return { text, changes, parseFailed: false };
}

// Rewrites the tracked workspace file in place (UTF-8, no BOM). No write when nothing changes.
export async function migrateWorkspaceFile(repositoryRoot: string, logger: Logger): Promise<boolean> {
    const workspaceFile = vscode.workspace.workspaceFile;
    if (!workspaceFile || workspaceFile.scheme !== "file") {
        logger.info("No *.code-workspace file is open; add { \"name\": \".external\", \"uri\": \"aldc-external:/\" } to your folders to mount the external sources.");
        return false;
    }
    const file = workspaceFile.fsPath;
    const relative = path.relative(path.resolve(repositoryRoot), path.resolve(file));
    if (relative.startsWith("..") || path.isAbsolute(relative)) {
        logger.info(`Workspace file ${file} is outside the repository ${repositoryRoot}; not migrated. Add { "name": ".external", "uri": "aldc-external:/" } to its folders manually.`);
        return false;
    }
    let original: string;
    try {
        original = (await fs.readFile(file, "utf8")).replace(/^\uFEFF/, "");
    } catch (error) {
        logger.warn(`Workspace file ${file} could not be read: ${(error as Error).message}`);
        return false;
    }
    const result = await migrateWorkspaceText(original, path.dirname(file));
    if (result.parseFailed) {
        const message = `${path.basename(file)} could not be parsed; left untouched. Manually add { "name": ".external", "uri": "aldc-external:/" } to "folders" and remove legacy BCQuality roots.`;
        logger.warn(message);
        void vscode.window?.showWarningMessage?.(message);
        return false;
    }
    if (result.changes.length === 0 || result.text === original) {
        return false;
    }
    await fs.writeFile(file, result.text, "utf8");
    for (const change of result.changes) {
        logger.info(`Workspace migration (${path.basename(file)}): ${change}`);
    }
    return true;
}
