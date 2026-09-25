import * as fs from "fs/promises";
import * as vscode from "vscode";
import { readBcqualityAldcConfig } from "../bcquality/aldcConfig";
import { resolveBcquality } from "../bcquality/resolve";
import { resolveContained } from "../bcquality/containment";
import { resolveAldcRepository } from "../env/gitRoot";

const toolName = "aprodaAldc_bcquality";

// State because the model must be told *why* nothing came back, never left to guess (finding B-6/B-5's
// lesson applied here): "disabled" and "unresolved" are distinct from a plain empty result.
export type BcqualityToolOutput =
    | { readonly status: "disabled"; readonly message: string }
    | { readonly status: "unresolved"; readonly message: string; readonly enabled: "auto" | boolean; readonly resolvedFrom?: string; readonly candidates: unknown[] }
    | { readonly status: "invalidPath"; readonly message: string }
    | { readonly status: "notFound"; readonly message: string }
    | { readonly status: "notAFile"; readonly message: string }
    | { readonly status: "tooLarge"; readonly message: string; readonly sizeBytes: number; readonly limitBytes: number }
    | { readonly status: "ok"; readonly operation: "read"; readonly path: string; readonly content: string }
    | { readonly status: "ok"; readonly operation: "list"; readonly path: string; readonly entries: { name: string; type: "file" | "directory" }[]; readonly truncated: boolean; readonly totalCount: number };

export interface BcqualityToolInput {
    readonly operation: "read" | "list";
    readonly path?: string;
}

// Sane, stated limits (per the scope): a knowledge file has no business being huge, and a directory
// listing must never flood the model's context.
export const maxReadBytes = 256 * 1024;
export const maxListEntries = 200;

export function registerBcqualityTool(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.lm.registerTool(toolName, new BcqualityTool()));
}

// The logic is exported separately from the vscode.LanguageModelTool wrapper so it can be unit-tested
// without mocking vscode.lm / LanguageModelToolResult.
export async function runBcqualityTool(input: BcqualityToolInput): Promise<BcqualityToolOutput> {
    // Read just the enabled flag first and short-circuit before any candidate probing (fs/aldc.yaml round-trips):
    // a disabled project must not have resolver work done on its behalf (§1.6 case 1). This is deliberately only
    // in the tool path -- "Show BCQuality Status" still calls resolveBcquality() directly so it can keep showing
    // the full candidate chain even while disabled.
    const repository = await resolveAldcRepository();
    const aldcConfig = await readBcqualityAldcConfig(repository);
    if (aldcConfig?.enabled === false) {
        return {
            status: "disabled",
            message: "BCQuality is disabled for this project (external.bcquality.enabled: false in aldc.yaml). No files are served."
        };
    }

    const resolution = await resolveBcquality(repository);
    if (!resolution.verified || !resolution.root) {
        return {
            status: "unresolved",
            message: "The BCQuality clone could not be resolved and verified from any known location. Run 'Aproda ALDC: Show BCQuality Status' or 'Aproda ALDC: Install / Update BCQuality'.",
            enabled: resolution.enabled,
            resolvedFrom: resolution.resolvedFrom,
            candidates: resolution.candidates
        };
    }

    const relativePath = input.path?.trim() || ".";
    const contained = await resolveContained(resolution.root, relativePath);
    if (!contained.ok || !contained.absolutePath) {
        return { status: "invalidPath", message: contained.reason ?? "Invalid path." };
    }

    return input.operation === "list"
        ? await listDirectory(relativePath, contained.absolutePath)
        : await readFile(relativePath, contained.absolutePath);
}

async function readFile(relativePath: string, absolutePath: string): Promise<BcqualityToolOutput> {
    let stats;
    try {
        stats = await fs.stat(absolutePath);
    } catch {
        return { status: "notFound", message: `No such file in the BCQuality clone: ${relativePath}` };
    }
    if (!stats.isFile()) {
        return { status: "notAFile", message: `Not a file (use operation "list" for directories): ${relativePath}` };
    }
    if (stats.size > maxReadBytes) {
        return { status: "tooLarge", message: `File exceeds the ${maxReadBytes}-byte limit.`, sizeBytes: stats.size, limitBytes: maxReadBytes };
    }
    const content = await fs.readFile(absolutePath, "utf8");
    return { status: "ok", operation: "read", path: relativePath, content };
}

async function listDirectory(relativePath: string, absolutePath: string): Promise<BcqualityToolOutput> {
    let dir;
    try {
        dir = await fs.opendir(absolutePath);
    } catch {
        return { status: "notFound", message: `No such directory in the BCQuality clone: ${relativePath}` };
    }

    // Bounded top-K instead of materialise-then-sort: `kept` never grows past maxListEntries, yet every
    // entry is still streamed through once, so totalCount stays exact (never a guessed/partial number)
    // even when the listing is truncated.
    const kept: { name: string; type: "file" | "directory" }[] = [];
    let totalCount = 0;
    for await (const dirent of dir) {
        totalCount++;
        insertSorted(kept, { name: dirent.name, type: dirent.isDirectory() ? "directory" as const : "file" as const });
    }

    return {
        status: "ok",
        operation: "list",
        path: relativePath,
        entries: kept,
        truncated: totalCount > maxListEntries,
        totalCount
    };
}

// Keeps `kept` sorted ascending by name and capped at maxListEntries, without ever sorting the full set.
function insertSorted(kept: { name: string; type: "file" | "directory" }[], item: { name: string; type: "file" | "directory" }): void {
    let low = 0;
    let high = kept.length;
    while (low < high) {
        const mid = (low + high) >>> 1;
        if (kept[mid].name.localeCompare(item.name) <= 0) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low >= maxListEntries) {
        return;
    }
    kept.splice(low, 0, item);
    if (kept.length > maxListEntries) {
        kept.pop();
    }
}

class BcqualityTool implements vscode.LanguageModelTool<BcqualityToolInput> {
    async prepareInvocation(options: vscode.LanguageModelToolInvocationPrepareOptions<BcqualityToolInput>): Promise<vscode.PreparedToolInvocation> {
        const target = options.input.path?.trim() || ".";
        return { invocationMessage: `${options.input.operation === "list" ? "Listing" : "Reading"} BCQuality: ${target}` };
    }

    async invoke(
        options: vscode.LanguageModelToolInvocationOptions<BcqualityToolInput>,
        _token: vscode.CancellationToken
    ): Promise<vscode.LanguageModelToolResult> {
        const output = await runBcqualityTool(options.input);
        return new vscode.LanguageModelToolResult([
            new vscode.LanguageModelTextPart(JSON.stringify(output, undefined, 2))
        ]);
    }
}
