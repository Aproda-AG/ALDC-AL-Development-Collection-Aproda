import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

// Same rule that sets the `aprodaAldc.isAlProject` context key: a workspace folder with app.json at its root.
export function isAlWorkspace(): boolean {
    return vscode.workspace.workspaceFolders?.some((folder) => fs.existsSync(path.join(folder.uri.fsPath, "app.json"))) ?? false;
}
