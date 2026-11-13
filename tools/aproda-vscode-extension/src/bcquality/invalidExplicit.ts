import * as vscode from "vscode";
import { Logger } from "../log";
import { BcqualityCandidate, BcqualityResolution, resolveBcquality } from "./resolve";

export interface InvalidExplicitCandidate {
    readonly source: "setting" | "environment";
    readonly path: string;
    readonly verdict: BcqualityCandidate["verdict"];
    readonly root: string;
    readonly resolvedFrom: string;
    readonly message: string;
}

// Pure (Q-6, A12): the `setting` / `environment` rungs are explicit user input. When one is set but not verified and a
// later rung serves BCQuality, the user should be told. `devRoot` and `aldcYaml` are defaults and never warn.
export function findInvalidExplicitCandidates(resolution: BcqualityResolution): InvalidExplicitCandidate[] {
    if (resolution.enabled === false || !resolution.verified || !resolution.root || !resolution.resolvedFrom) {
        return [];
    }
    const result: InvalidExplicitCandidate[] = [];
    for (const candidate of resolution.candidates) {
        if ((candidate.source !== "setting" && candidate.source !== "environment") || !candidate.path || candidate.verdict === "verified") {
            continue;
        }
        const label = candidate.source === "setting" ? "aprodaAldc.bcquality.path" : "BCQUALITY_HOME";
        result.push({
            source: candidate.source,
            path: candidate.path,
            verdict: candidate.verdict,
            root: resolution.root,
            resolvedFrom: resolution.resolvedFrom,
            message: `${label} points to ${candidate.path} (${candidate.verdict}); BCQuality is served from ${resolution.root} (${resolution.resolvedFrom}).`
        });
    }
    return result;
}

// One log line and one notification per distinct value and window.
const shownValues = new Set<string>();

export async function warnInvalidExplicitCandidates(logger: Logger, resolution?: BcqualityResolution): Promise<void> {
    const findings = findInvalidExplicitCandidates(resolution ?? await resolveBcquality());
    for (const finding of findings) {
        const key = `${finding.source}:${finding.path}`;
        if (shownValues.has(key)) {
            continue;
        }
        shownValues.add(key);
        logger.warn(finding.message);
        const openSettings = "Open Settings";
        const showStatus = "Show BCQuality Status";
        void Promise.resolve(vscode.window.showWarningMessage(finding.message, openSettings, showStatus)).then((choice) => {
            if (choice === openSettings) {
                void vscode.commands.executeCommand("workbench.action.openSettings", "aprodaAldc.bcquality.path");
            } else if (choice === showStatus) {
                void vscode.commands.executeCommand("aprodaAldc.showBcQualityStatus");
            }
        });
    }
}
