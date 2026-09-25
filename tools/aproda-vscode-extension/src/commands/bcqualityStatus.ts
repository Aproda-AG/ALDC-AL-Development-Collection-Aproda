import * as path from "path";
import * as fs from "fs/promises";
import * as vscode from "vscode";
import { resolveBcquality, BcqualitySource, BcqualityVerdict } from "../bcquality/resolve";
import { readBcqualityAldcConfig } from "../bcquality/aldcConfig";
import { resolveAldcRepository } from "../env/gitRoot";

// The UI half of "fail loudly" (E-006 §1.3): makes the whole resolver chain visible in one click, and
// shows the declared aldc.yaml home next to the live resolved root instead of ever writing one into the other.
export async function showBcqualityStatus(): Promise<void> {
    const repository = await resolveAldcRepository();
    const resolution = await resolveBcquality(repository);
    const declaredHome = repository.state === "configured"
        ? (await readBcqualityAldcConfig(repository))?.home
        : undefined;
    const junctionPath = repository.state === "configured"
        ? path.join(repository.repositoryRoot, ".external", "bcquality")
        : undefined;
    const junctionExists = junctionPath ? await isSymlink(junctionPath) : false;

    const summaryItems: vscode.QuickPickItem[] = [
        { label: "Resolved root", description: resolution.verified ? resolution.root : "(none)", detail: resolution.resolvedFrom ? `via ${sourceLabel(resolution.resolvedFrom)}` : undefined },
        { label: "Declared (aldc.yaml → external.bcquality.home)", description: declaredHome ?? "(not set)" },
        { label: ".external/bcquality junction", description: junctionExists ? "exists" : "does not exist" }
    ];

    const candidateItems: vscode.QuickPickItem[] = resolution.candidates.map((candidate) => ({
        label: `${verdictIcon(candidate.verdict)} ${sourceLabel(candidate.source)}`,
        description: verdictLabel(candidate.verdict),
        detail: candidate.path ?? "(not set)"
    }));

    const items: vscode.QuickPickItem[] = [
        { label: "Summary", kind: vscode.QuickPickItemKind.Separator },
        ...summaryItems,
        { label: "Resolver chain (in precedence order)", kind: vscode.QuickPickItemKind.Separator },
        ...candidateItems
    ];

    if (!resolution.verified) {
        items.push(
            { label: "Actions", kind: vscode.QuickPickItemKind.Separator },
            { label: "$(cloud-download) Install / Update BCQuality...", description: "Runs Aproda ALDC: Install / Update BCQuality" }
        );
    }

    const selected = await vscode.window.showQuickPick(items, {
        placeHolder: resolution.enabled === false
            ? "BCQuality is disabled for this project (external.bcquality.enabled: false)"
            : resolution.verified
                ? `BCQuality is active, resolved from ${sourceLabel(resolution.resolvedFrom!)}`
                : "BCQuality could not be resolved",
        matchOnDescription: true,
        matchOnDetail: true
    });

    if (selected?.label.includes("Install / Update BCQuality")) {
        await vscode.commands.executeCommand("aprodaAldc.installBcQuality");
    }
}

function sourceLabel(source: BcqualitySource): string {
    switch (source) {
        case "setting": return "VS Code setting (aprodaAldc.bcquality.path)";
        case "workspaceFolder": return "Mounted workspace folder";
        case "environment": return "$BCQUALITY_HOME";
        case "devRoot": return "<devRoot>/BCQuality-Aproda";
        case "aldcYaml": return "aldc.yaml → external.bcquality.home";
    }
}

function verdictLabel(verdict: BcqualityVerdict): string {
    switch (verdict) {
        case "verified": return "verified";
        case "noEntryPoint": return "no skills/entry.md";
        case "missing": return "directory missing";
        case "notSet": return "not set";
    }
}

function verdictIcon(verdict: BcqualityVerdict): string {
    return verdict === "verified" ? "$(check)" : "$(circle-slash)";
}

async function isSymlink(candidate: string): Promise<boolean> {
    try {
        return (await fs.lstat(candidate)).isSymbolicLink();
    } catch {
        return false;
    }
}
