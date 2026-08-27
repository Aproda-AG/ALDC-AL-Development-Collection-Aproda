import * as vscode from "vscode";
import { Channel, devRoot, forkPath, pinnedVersion, startupCheckIntervalHours, updateGlobal } from "../config";
import { directoryExists, proposeDevRoot } from "../env/devRoot";
import { resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { runDoctor } from "./doctor";
import { LayerSource } from "../source/layerSource";

const setupCompletedKey = "setupCompleted";

export async function resetSetupState(context: vscode.ExtensionContext): Promise<void> {
    await context.globalState.update(setupCompletedKey, undefined);
}

export async function offerInitialSetup(context: vscode.ExtensionContext, logger: Logger, layerSource: LayerSource): Promise<void> {
    if (context.globalState.get<boolean>(setupCompletedKey)) {
        return;
    }
    const choice = await vscode.window.showInformationMessage("Configure Aproda ALDC settings for this VS Code installation?", "Configure Settings", "Later");
    await context.globalState.update(setupCompletedKey, true);
    if (choice === "Configure Settings") {
        await runSetupWizard(context, logger, layerSource);
    }
}

export async function runSetupWizard(context: vscode.ExtensionContext, logger: Logger, layerSource: LayerSource): Promise<void> {
    await runDoctor(context, logger, layerSource);
    const repositoryRoot = await resolveTargetRepo();
    const proposedRoot = devRoot() || await proposeDevRoot(repositoryRoot) || "";
    const selectedRoot = await vscode.window.showInputBox({
        title: "Aproda ALDC: Developer Root",
        prompt: "Used by future Aproda ALDC tooling. Leave blank to configure it later.",
        value: proposedRoot,
        ignoreFocusOut: true
    });
    if (selectedRoot === undefined) {
        return;
    }
    const normalizedRoot = selectedRoot.trim();
    if (normalizedRoot && !await directoryExists(normalizedRoot)) {
        const choice = await vscode.window.showWarningMessage(`Developer root does not exist: ${normalizedRoot}`, "Use Anyway", "Cancel");
        if (choice !== "Use Anyway") {
            return;
        }
    }
    await updateGlobal("devRoot", normalizedRoot);

    const selectedMode = await vscode.window.showQuickPick([
        { label: "Managed cache", value: "managed" as const, description: "Recommended. The extension maintains a clean local clone." },
        { label: "Local fork", value: "localFork" as const, description: "For Aproda layer maintainers." }
    ], { title: "Aproda ALDC: Layer Source", ignoreFocusOut: true });
    if (!selectedMode) {
        return;
    }
    await updateGlobal("source.mode", selectedMode.value);
    if (selectedMode.value === "localFork" && !forkPath()) {
        const selectedFolder = await vscode.window.showOpenDialog({ canSelectFiles: false, canSelectFolders: true, canSelectMany: false, openLabel: "Select Local Aproda Fork" });
        if (!selectedFolder?.[0]) {
            return;
        }
        await updateGlobal("source.forkPath", selectedFolder[0].fsPath);
    }

    const selectedChannel = await vscode.window.showQuickPick([
        { label: "Release", value: "release" as const },
        { label: "Edge", value: "edge" as const },
        { label: "Pinned", value: "pinned" as const }
    ], { title: "Aproda ALDC: Layer Channel", ignoreFocusOut: true });
    if (!selectedChannel) {
        return;
    }
    await updateGlobal("channel", selectedChannel.value as Channel);
    if (selectedChannel.value === "pinned") {
        const version = await vscode.window.showInputBox({
            title: "Aproda ALDC: Pinned Layer Version",
            prompt: "Enter the layer version to use.",
            value: pinnedVersion(),
            validateInput: (value) => /^\d+\.\d+\.\d+_aproda\.\d+$/.test(value.trim()) ? undefined : "Enter a version such as 1.2.0_aproda.9.",
            ignoreFocusOut: true
        });
        if (version === undefined) {
            return;
        }
        await updateGlobal("pinnedVersion", version.trim());
    }

    const selectedStartupCheck = await vscode.window.showQuickPick([
        { label: "Enable startup update checks", value: true },
        { label: "Disable startup update checks", value: false }
    ], { title: "Aproda ALDC: Startup Update Check", ignoreFocusOut: true });
    if (!selectedStartupCheck) {
        return;
    }
    await updateGlobal("startupCheck.enabled", selectedStartupCheck.value);
    if (selectedStartupCheck.value) {
        const interval = await vscode.window.showInputBox({
            title: "Aproda ALDC: Update Check Interval",
            prompt: "Minimum hours between automatic checks.",
            value: String(startupCheckIntervalHours()),
            validateInput: (value) => /^\d+$/.test(value) && Number(value) >= 1 ? undefined : "Enter a whole number of at least 1.",
            ignoreFocusOut: true
        });
        if (interval === undefined) {
            return;
        }
        await updateGlobal("startupCheck.intervalHours", Number(interval));
    }
    await context.globalState.update(setupCompletedKey, true);
    logger.info("Aproda ALDC settings wizard completed.");
    void vscode.window.showInformationMessage("Aproda ALDC settings were saved.");
}