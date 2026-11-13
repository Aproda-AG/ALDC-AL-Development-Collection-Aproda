import { spawn, SpawnOptions } from "child_process";
import * as fs from "fs/promises";
import * as path from "path";
import * as vscode from "vscode";
import { resolveBcquality } from "../bcquality/resolve";
import { describeUnresolved, ExternalFileSystemProvider, externalScheme } from "../external/externalFileSystemProvider";

export type RevealSpawner = (command: string, args: string[], options: SpawnOptions) => void;

export interface RevealCommand {
    readonly command: string;
    readonly args: string[];
    readonly options: SpawnOptions;
}

// Per-platform argument builders, pure so the quoting can be tested without spawning anything.
export function buildRevealCommand(diskPath: string, platform: NodeJS.Platform = process.platform): RevealCommand {
    if (platform === "win32") {
        // Verbatim: explorer.exe parses `/select,"<path>"` itself and mishandles generic quoting of paths with spaces.
        return { command: "explorer.exe", args: [`/select,"${diskPath}"`], options: { windowsVerbatimArguments: true, detached: true, stdio: "ignore" } };
    }
    if (platform === "darwin") {
        return { command: "open", args: ["-R", diskPath], options: { detached: true, stdio: "ignore" } };
    }
    return { command: "xdg-open", args: [path.dirname(diskPath)], options: { detached: true, stdio: "ignore" } };
}

const defaultSpawner: RevealSpawner = (command, args, options) => {
    const child = spawn(command, args, options);
    child.on("error", () => undefined);
    child.unref();
};

// Reveals a file of the virtual mount at its real location. No argument: the BCQuality entry point of the
// resolved clone. With an `aldc-external:` URI (Explorer context menu): the real file behind it.
export async function revealBcqualityClone(provider: ExternalFileSystemProvider, arg?: vscode.Uri, spawner: RevealSpawner = defaultSpawner): Promise<void> {
    try {
        if (arg && arg.scheme === externalScheme) {
            await reveal(await provider.resolveToDisk(arg), spawner);
            return;
        }
        const resolution = await resolveBcquality();
        if (!resolution.verified || !resolution.root) {
            void vscode.window.showWarningMessage(describeUnresolved(resolution));
            return;
        }
        await reveal(path.join(resolution.root, resolution.entryPoint), spawner);
    } catch (error) {
        void vscode.window.showWarningMessage(error instanceof Error ? error.message : String(error));
    }
}

// Not `revealFileInOS`: with the Explorer focused it prefers the Explorer selection (aldc-external: URIs) over its argument.
async function reveal(diskPath: string, spawner: RevealSpawner): Promise<void> {
    try {
        await fs.access(diskPath);
    } catch {
        void vscode.window.showWarningMessage(`Cannot reveal ${diskPath}: the path does not exist.`);
        return;
    }
    const { command, args, options } = buildRevealCommand(diskPath);
    spawner(command, args, options);
}
