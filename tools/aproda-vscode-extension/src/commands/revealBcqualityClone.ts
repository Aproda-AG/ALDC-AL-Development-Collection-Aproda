import * as path from "path";
import * as vscode from "vscode";
import { resolveBcquality } from "../bcquality/resolve";
import { describeUnresolved, ExternalFileSystemProvider, externalScheme } from "../external/externalFileSystemProvider";

// Reveals a file of the virtual mount at its real location. No argument: the BCQuality entry point of the
// resolved clone. With an `aldc-external:` URI (Explorer context menu): the real file behind it.
export async function revealBcqualityClone(provider: ExternalFileSystemProvider, arg?: vscode.Uri): Promise<void> {
    try {
        if (arg && arg.scheme === externalScheme) {
            await reveal(await provider.resolveToDisk(arg));
            return;
        }
        const resolution = await resolveBcquality();
        if (!resolution.verified || !resolution.root) {
            void vscode.window.showWarningMessage(describeUnresolved(resolution));
            return;
        }
        await reveal(path.join(resolution.root, resolution.entryPoint));
    } catch (error) {
        void vscode.window.showWarningMessage(error instanceof Error ? error.message : String(error));
    }
}

async function reveal(diskPath: string): Promise<void> {
    await vscode.commands.executeCommand("revealFileInOS", vscode.Uri.file(diskPath));
}
