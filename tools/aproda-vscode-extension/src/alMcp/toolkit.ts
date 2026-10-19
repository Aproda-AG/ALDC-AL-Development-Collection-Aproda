import * as fs from "fs";
import * as path from "path";
import YAML from "yaml";

export interface ToolkitInfo {
    readonly toolkitRoot: string | undefined;
    readonly layerVersion: string;
}

// toolkitRoot in aldc.yaml is relative to the repository root (".github" in a consuming project, "." in the
// fork). When it is missing, aldc.yaml itself lives at <toolkitRoot>/aldc.yaml (T-33), so its folder is the root.
export function readToolkitInfo(repositoryRoot: string, configurationPath: string): ToolkitInfo {
    let toolkitRoot: string | undefined;
    let layerVersion = "";
    try {
        const document: unknown = YAML.parse(fs.readFileSync(configurationPath, "utf8"));
        if (typeof document === "object" && document !== null) {
            const record = document as Record<string, unknown>;
            if (typeof record.toolkitRoot === "string" && record.toolkitRoot.trim()) {
                toolkitRoot = path.resolve(repositoryRoot, record.toolkitRoot.trim());
            }
            const aproda = record.aproda;
            if (typeof aproda === "object" && aproda !== null && typeof (aproda as Record<string, unknown>).layerVersion === "string") {
                layerVersion = (aproda as Record<string, string>).layerVersion;
            }
        }
    } catch {
        toolkitRoot = undefined;
    }
    toolkitRoot ??= path.dirname(configurationPath);
    // The starter is run as PowerShell: never take it from outside the repository.
    const relative = path.relative(repositoryRoot, toolkitRoot);
    if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
        return { toolkitRoot: undefined, layerVersion };
    }
    return { toolkitRoot, layerVersion };
}

export function resolveToolkitRoot(repositoryRoot: string, configurationPath: string): string | undefined {
    return readToolkitInfo(repositoryRoot, configurationPath).toolkitRoot;
}
