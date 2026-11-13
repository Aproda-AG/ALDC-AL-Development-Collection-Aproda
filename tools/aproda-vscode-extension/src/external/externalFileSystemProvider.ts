import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { externalMount } from "../config";
import { readExternalSourceNames } from "../bcquality/aldcConfig";
import { resolveContained } from "../bcquality/containment";
import { BcqualityResolution, resolveBcquality } from "../bcquality/resolve";
import { AldcRepositoryResolution, resolveAldcRepository } from "../env/gitRoot";

export const externalScheme = "aldc-external";
export const externalWrapperFolder = ".external";
export const readOnlyMessage = "aldc-external:/ is read-only";
export const noRepositoryMessage = "No ALDC repository in this window.";

interface SourceState {
    readonly active: boolean;
    readonly root?: string;
    readonly unavailable?: string;
}

interface ExternalSource {
    readonly name: string;
    state(repository: AldcRepositoryResolution): Promise<SourceState>;
}

export function describeUnresolved(resolution: BcqualityResolution): string {
    const tried = resolution.candidates
        .map((candidate) => `${candidate.source}=${candidate.path ?? "unset"}[${candidate.verdict}]`)
        .join("; ");
    return `BCQuality clone not resolved. Tried: ${tried}`;
}

const bcqualitySource: ExternalSource = {
    name: "bcquality",
    async state(repository) {
        if (externalMount() === "none") {
            return { active: false };
        }
        const resolution = await resolveBcquality(repository);
        if (resolution.enabled === false) {
            return { active: false };
        }
        if (resolution.verified && resolution.root) {
            return { active: true, root: resolution.root };
        }
        return { active: true, unavailable: describeUnresolved(resolution) };
    }
};

// Static registry (G-1a): further sources are added here, an `external.<name>` block without an entry is ignored.
const sources: readonly ExternalSource[] = [bcqualitySource];

type Located =
    | { readonly kind: "root"; readonly repositoryRoot: string; readonly external: string }
    | { readonly kind: "disk"; readonly absolute: string; readonly via: "source" | "passthrough" };

export interface ExternalProviderLog {
    info(message: string): void;
}

let providerRegistered = false;

export function isExternalProviderRegistered(): boolean {
    return providerRegistered;
}

export class ExternalFileSystemProvider implements vscode.FileSystemProvider {
    private readonly emitter = new vscode.EventEmitter<vscode.FileChangeEvent[]>();
    private readonly reportedSources = new Set<string>();

    readonly onDidChangeFile = this.emitter.event;

    constructor(private readonly log: ExternalProviderLog = { info: () => undefined }) { }

    dispose(): void {
        this.emitter.dispose();
    }

    // Fired when the resolved root of a source, `external.mount` or aldc.yaml changes (§2.6). The provider
    // keeps no content cache, so a refresh only tells VS Code to re-read.
    refresh(): void {
        const events: vscode.FileChangeEvent[] = [{ type: vscode.FileChangeType.Changed, uri: rootUri("/") }];
        for (const source of sources) {
            events.push({ type: vscode.FileChangeType.Changed, uri: rootUri(`/${source.name}`) });
        }
        this.emitter.fire(events);
    }

    watch(): vscode.Disposable {
        return new vscode.Disposable(() => undefined);
    }

    async stat(uri: vscode.Uri): Promise<vscode.FileStat> {
        const located = await this.locate(uri);
        if (located.kind === "root") {
            return { type: vscode.FileType.Directory, ctime: 0, mtime: 0, size: 0, permissions: vscode.FilePermission.Readonly };
        }
        try {
            const stat = await fs.stat(located.absolute);
            return {
                type: stat.isDirectory() ? vscode.FileType.Directory : vscode.FileType.File,
                ctime: stat.ctimeMs,
                mtime: stat.mtimeMs,
                size: stat.size,
                permissions: vscode.FilePermission.Readonly
            };
        } catch (error) {
            throw mapFsError(error, uri);
        }
    }

    async readDirectory(uri: vscode.Uri): Promise<[string, vscode.FileType][]> {
        const located = await this.locate(uri);
        if (located.kind === "root") {
            return this.listRoot(located.repositoryRoot, located.external);
        }
        try {
            const dirents = await fs.readdir(located.absolute, { withFileTypes: true });
            const entries: [string, vscode.FileType][] = [];
            for (const dirent of dirents) {
                if (dirent.isSymbolicLink()) {
                    if (located.via === "passthrough") {
                        continue;
                    }
                    try {
                        const target = await fs.stat(path.join(located.absolute, dirent.name));
                        entries.push([dirent.name, target.isDirectory() ? vscode.FileType.Directory : vscode.FileType.File]);
                    } catch {
                        // dangling link: not listed
                    }
                    continue;
                }
                entries.push([dirent.name, dirent.isDirectory() ? vscode.FileType.Directory : vscode.FileType.File]);
            }
            return entries;
        } catch (error) {
            throw mapFsError(error, uri);
        }
    }

    async readFile(uri: vscode.Uri): Promise<Uint8Array> {
        const located = await this.locate(uri);
        if (located.kind === "root") {
            throw vscode.FileSystemError.FileIsADirectory(uri);
        }
        try {
            return await fs.readFile(located.absolute);
        } catch (error) {
            throw mapFsError(error, uri);
        }
    }

    writeFile(): never {
        throw vscode.FileSystemError.NoPermissions(readOnlyMessage);
    }

    createDirectory(): never {
        throw vscode.FileSystemError.NoPermissions(readOnlyMessage);
    }

    delete(): never {
        throw vscode.FileSystemError.NoPermissions(readOnlyMessage);
    }

    rename(): never {
        throw vscode.FileSystemError.NoPermissions(readOnlyMessage);
    }

    // Maps an `aldc-external:` URI to the real path it is served from (Reveal command). Throws like the provider does.
    async resolveToDisk(uri: vscode.Uri): Promise<string> {
        const located = await this.locate(uri);
        return located.kind === "root" ? located.external : located.absolute;
    }

    private async locate(uri: vscode.Uri): Promise<Located> {
        const repository = await resolveAldcRepository();
        if (repository.state !== "configured") {
            throw vscode.FileSystemError.Unavailable(noRepositoryMessage);
        }
        const segments = segmentsOf(uri);
        if (!segments) {
            throw vscode.FileSystemError.FileNotFound(uri);
        }
        const external = path.join(repository.repositoryRoot, externalWrapperFolder);
        if (segments.length === 0) {
            return { kind: "root", repositoryRoot: repository.repositoryRoot, external };
        }

        const source = findSource(segments[0]);
        if (source) {
            const state = await source.state(repository);
            if (!state.active) {
                throw vscode.FileSystemError.FileNotFound(uri);
            }
            if (!state.root) {
                throw vscode.FileSystemError.Unavailable(state.unavailable ?? "Source not resolved.");
            }
            const contained = await resolveContained(state.root, segments.slice(1).join("/"));
            if (!contained.ok || !contained.absolutePath) {
                throw vscode.FileSystemError.FileNotFound(uri);
            }
            return { kind: "disk", absolute: contained.absolutePath, via: "source" };
        }

        const contained = await resolveContained(external, segments.join("/"));
        if (!contained.ok || !contained.absolutePath) {
            throw vscode.FileSystemError.FileNotFound(uri);
        }
        // Reparse points (junction/symlink) directly below .external are neither listed nor followed.
        if (await isLink(path.join(external, segments[0]))) {
            throw vscode.FileSystemError.FileNotFound(uri);
        }
        return { kind: "disk", absolute: contained.absolutePath, via: "passthrough" };
    }

    private async listRoot(repositoryRoot: string, external: string): Promise<[string, vscode.FileType][]> {
        const entries: [string, vscode.FileType][] = [];
        try {
            for (const dirent of await fs.readdir(external, { withFileTypes: true })) {
                if (dirent.isSymbolicLink() || findSource(dirent.name)) {
                    continue;
                }
                entries.push([dirent.name, dirent.isDirectory() ? vscode.FileType.Directory : vscode.FileType.File]);
            }
        } catch {
            // no real .external folder: only the virtual sources are listed
        }

        const repository = await resolveAldcRepository();
        for (const source of sources) {
            if ((await source.state(repository)).active) {
                entries.push([source.name, vscode.FileType.Directory]);
            }
        }
        await this.reportUnknownSources(repository, repositoryRoot);
        return entries;
    }

    private async reportUnknownSources(repository: AldcRepositoryResolution, repositoryRoot: string): Promise<void> {
        for (const name of await readExternalSourceNames(repository)) {
            if (!sources.some((source) => source.name === name) && !this.reportedSources.has(name)) {
                this.reportedSources.add(name);
                this.log.info(`aldc.yaml external.${name} (${repositoryRoot}) has no registered source in this extension; ignored.`);
            }
        }
    }
}

export function registerExternalFileSystemProvider(
    context: vscode.ExtensionContext,
    log: ExternalProviderLog
): ExternalFileSystemProvider {
    const provider = new ExternalFileSystemProvider(log);
    context.subscriptions.push(
        provider,
        vscode.workspace.registerFileSystemProvider(externalScheme, provider, { isCaseSensitive: false, isReadonly: true })
    );
    providerRegistered = true;
    return provider;
}

function rootUri(uriPath: string): vscode.Uri {
    return vscode.Uri.from({ scheme: externalScheme, path: uriPath });
}

function findSource(name: string): ExternalSource | undefined {
    const lower = name.toLowerCase();
    return sources.find((source) => source.name.toLowerCase() === lower);
}

// POSIX-style normalisation done by hand: path.posix.normalize clamps "/.." to "/", but a ".." that leaves the
// root must be a FileNotFound, never content from somewhere else.
function segmentsOf(uri: vscode.Uri): string[] | undefined {
    const raw = uri.authority ? `/${uri.authority}${uri.path}` : uri.path;
    const result: string[] = [];
    for (const part of raw.split("/")) {
        if (part === "" || part === ".") {
            continue;
        }
        if (part === "..") {
            if (result.length === 0) {
                return undefined;
            }
            result.pop();
            continue;
        }
        result.push(part);
    }
    return result;
}

async function isLink(target: string): Promise<boolean> {
    try {
        return (await fs.lstat(target)).isSymbolicLink();
    } catch {
        return false;
    }
}

function mapFsError(error: unknown, uri: vscode.Uri): Error {
    const code = (error as NodeJS.ErrnoException | undefined)?.code;
    if (code === "ENOENT" || code === "ENOTDIR") {
        return vscode.FileSystemError.FileNotFound(uri);
    }
    if (code === "EISDIR") {
        return vscode.FileSystemError.FileIsADirectory(uri);
    }
    return vscode.FileSystemError.Unavailable(error instanceof Error ? error.message : String(error));
}
