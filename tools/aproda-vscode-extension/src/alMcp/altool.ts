import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

export const alExtensionId = "ms-dynamics-smb.al";

export interface AlExtensionInfo {
    readonly path: string;
    readonly version: string;
}

export function getAlExtension(): AlExtensionInfo | undefined {
    const extension = vscode.extensions.getExtension(alExtensionId);
    if (!extension) {
        return undefined;
    }
    const version = (extension.packageJSON as { version?: unknown } | undefined)?.version;
    return { path: extension.extensionPath, version: typeof version === "string" ? version : "" };
}

export type AltoolDescription =
    | { readonly state: "found"; readonly binary: string; readonly version: string }
    | { readonly state: "missingBinary"; readonly extensionPath: string }
    | { readonly state: "notInstalled" };

// Spec §2.4 step 1 only: the active AL extension is authoritative and is what the provider passes to the starter.
// Steps 2-4 (installed extensions, dotnet tool) run in the starter when the AL extension is not installed.
export function describeActiveAltool(): AltoolDescription {
    const extension = getAlExtension();
    if (!extension) {
        return { state: "notInstalled" };
    }
    for (const relative of [path.join("bin", "altool.exe"), path.join("bin", "win32", "altool.exe")]) {
        const candidate = path.join(extension.path, relative);
        if (fs.existsSync(candidate)) {
            return { state: "found", binary: candidate, version: extension.version };
        }
    }
    return { state: "missingBinary", extensionPath: extension.path };
}
