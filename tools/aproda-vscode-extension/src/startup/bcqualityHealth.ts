import * as vscode from "vscode";
import { resolveBcquality } from "../bcquality/resolve";

const disabledKey = "bcqualityMissingCheckDisabled";

// Self-heal for the common real cases (E-006 §1.3): the configured clone was deleted/moved ("missing"), or
// it exists but is not a BCQuality clone -- a half-cloned or corrupted checkout ("noEntryPoint"). Silent in
// the ordinary "nothing configured/installed yet" state -- only the "setting" rung is checked, and only
// those two verdicts are abnormal enough to notify about.
export async function checkBcqualitySelfHeal(context: vscode.ExtensionContext): Promise<void> {
    if (context.workspaceState.get<boolean>(disabledKey)) {
        return;
    }
    const resolution = await resolveBcquality();
    const settingCandidate = resolution.candidates.find((candidate) => candidate.source === "setting");
    if (settingCandidate?.verdict !== "missing" && settingCandidate?.verdict !== "noEntryPoint") {
        return;
    }

    const message = settingCandidate.verdict === "missing"
        ? `The configured BCQuality clone no longer exists at ${settingCandidate.path}.`
        : `The configured BCQuality path exists at ${settingCandidate.path}, but it does not look like a BCQuality clone (missing ${resolution.entryPoint}).`;

    const selection = await vscode.window.showWarningMessage(
        message,
        "Install / Update BCQuality",
        "Later",
        "Never for this project"
    );
    if (selection === "Install / Update BCQuality") {
        await vscode.commands.executeCommand("aprodaAldc.installBcQuality");
    }
    if (selection === "Never for this project") {
        await context.workspaceState.update(disabledKey, true);
    }
}
