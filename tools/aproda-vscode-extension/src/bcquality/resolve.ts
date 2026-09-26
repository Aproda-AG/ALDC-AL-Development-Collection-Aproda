import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { bcqualityPath, devRoot } from "../config";
import { directoryExists } from "../env/devRoot";
import { AldcRepositoryResolution, resolveAldcRepository } from "../env/gitRoot";
import { readBcqualityAldcConfig } from "./aldcConfig";

const defaultEntryPoint = "skills/entry.md";
// Wrapper subfolder name used by the .external/ layout (T-29): the junction lives one level below the mounted root.
const wrapperSubfolder = "bcquality";

export type BcqualitySource = "setting" | "workspaceFolder" | "environment" | "devRoot" | "aldcYaml";
export type BcqualityVerdict = "verified" | "noEntryPoint" | "missing" | "notSet";

export interface BcqualityCandidate {
    readonly source: BcqualitySource;
    readonly path?: string;
    readonly verdict: BcqualityVerdict;
    // Only set when a verified candidate is reached through a link (e.g. the .external/bcquality junction)
    // and its real location differs from the probed path -- that real location is what `root` resolves to.
    readonly realPath?: string;
}

export interface BcqualityResolution {
    readonly root?: string;
    readonly resolvedFrom?: BcqualitySource;
    readonly verified: boolean;
    readonly enabled: "auto" | boolean;
    readonly entryPoint: string;
    readonly candidates: BcqualityCandidate[];
}

// Precedence (D-49): setting -> mounted workspace folder -> $BCQUALITY_HOME -> <devRoot>/BCQuality-Aproda -> aldc.yaml home.
// Every rung is probed (never trusted unverified) and recorded, even when not set, so a later "why is BCQuality
// not active?" view can be built on `candidates` without re-resolving.
export async function resolveBcquality(repository?: AldcRepositoryResolution): Promise<BcqualityResolution> {
    const repositoryResolution = repository ?? await resolveAldcRepository();
    const aldcConfig = await readBcqualityAldcConfig(repositoryResolution);
    const entryPoint = aldcConfig?.entryPoint ?? defaultEntryPoint;
    const enabled = aldcConfig?.enabled ?? "auto";

    const candidates: BcqualityCandidate[] = [];

    candidates.push(await probe("setting", asAbsolute(bcqualityPath()), entryPoint));
    candidates.push(...await workspaceFolderCandidates(entryPoint));
    candidates.push(await probe("environment", asAbsolute(process.env.BCQUALITY_HOME), entryPoint));

    const devRootValue = devRoot();
    candidates.push(await probe("devRoot", devRootValue ? path.join(devRootValue, "BCQuality-Aproda") : undefined, entryPoint));

    const repositoryRoot = repositoryResolution.state === "configured" ? repositoryResolution.repositoryRoot : undefined;
    const declaredHome = repositoryRoot && aldcConfig?.home ? path.resolve(repositoryRoot, aldcConfig.home) : undefined;
    candidates.push(await probe("aldcYaml", declaredHome, entryPoint));

    const verified = candidates.find((candidate) => candidate.verdict === "verified");

    return {
        root: verified ? (verified.realPath ?? verified.path) : undefined,
        resolvedFrom: verified?.source,
        verified: verified !== undefined,
        enabled,
        entryPoint,
        candidates
    };
}

async function workspaceFolderCandidates(entryPoint: string): Promise<BcqualityCandidate[]> {
    const folders = vscode.workspace.workspaceFolders ?? [];
    if (folders.length === 0) {
        return [{ source: "workspaceFolder", verdict: "notSet" }];
    }
    const candidates: BcqualityCandidate[] = [];
    for (const folder of folders) {
        candidates.push(await probe("workspaceFolder", folder.uri.fsPath, entryPoint));
        candidates.push(await probe("workspaceFolder", path.join(folder.uri.fsPath, wrapperSubfolder), entryPoint));
    }
    return candidates;
}

function asAbsolute(value: string | undefined): string | undefined {
    return value?.trim() ? path.resolve(value.trim()) : undefined;
}

async function probe(source: BcqualitySource, candidatePath: string | undefined, entryPoint: string): Promise<BcqualityCandidate> {
    if (!candidatePath) {
        return { source, verdict: "notSet" };
    }
    if (!await directoryExists(candidatePath)) {
        return { source, path: candidatePath, verdict: "missing" };
    }
    if (!await fileExists(path.join(candidatePath, entryPoint))) {
        return { source, path: candidatePath, verdict: "noEntryPoint" };
    }
    const realPath = await canonicalize(candidatePath);
    return { source, path: candidatePath, verdict: "verified", realPath };
}

// A verified candidate must canonicalise to its real filesystem location before it is trusted as `root`:
// otherwise a link (e.g. the .external/bcquality junction) can be reported as the canonical clone, and later
// get written back as a link's own target. Only resolved when the probed path is itself a link -- calling
// realpath() on an ordinary directory can rewrite Windows 8.3 short-name segments (e.g. from os.tmpdir())
// into their long form, turning an unrelated path into a false "difference". realpath() failing (broken
// link, permissions) must never turn an otherwise-working candidate into a failure -- it just degrades to
// reporting the probed path as-is.
async function canonicalize(candidatePath: string): Promise<string | undefined> {
    try {
        if (!(await fs.lstat(candidatePath)).isSymbolicLink()) {
            return undefined;
        }
        const real = await fs.realpath(candidatePath);
        return stripLongPathPrefix(real);
    } catch {
        return undefined;
    }
}

// Windows realpath() returns junction/symlink targets with the "\\?\" long-path prefix; strip it so the
// result compares and joins like an ordinary path everywhere else in the extension.
function stripLongPathPrefix(candidatePath: string): string {
    return candidatePath.replace(/^\\\\\?\\/, "");
}

async function fileExists(candidate: string): Promise<boolean> {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}
