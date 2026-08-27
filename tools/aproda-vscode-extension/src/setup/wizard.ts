import * as vscode from "vscode";
import * as path from "path";
import { bcqualityPath, Channel, channel, devRoot, forkPath, pinnedVersion, sourceMode, startupCheckIntervalHours, startupChecksEnabled, updateGlobal } from "../config";
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
    const choice = await vscode.window.showInformationMessage(
        "Welcome to Aproda ALDC. Open the guided setup to configure your environment and initialize a project.",
        "Getting Started",
        "Later"
    );
    await context.globalState.update(setupCompletedKey, true);
    if (choice === "Getting Started") {
        await vscode.commands.executeCommand("aprodaAldc.openWalkthrough");
    }
}

export async function runSetupWizard(context: vscode.ExtensionContext, logger: Logger, layerSource: LayerSource): Promise<void> {
    await runDoctor(context, logger, layerSource);
    const repositoryRoot = await resolveTargetRepo();
    const proposedRoot = devRoot() || await proposeDevRoot(repositoryRoot) || "";
    const selectedRoot = await vscode.window.showInputBox({
        title: "Aproda ALDC: Developer Root",
        prompt: "Base folder for shared Aproda tooling, including the default BCQuality-Aproda location. Leave blank to configure it later.",
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
        quickPickItem("Managed cache", "managed", sourceMode(), "managed", "Keeps an extension-managed local copy of the approved layer release."),
        quickPickItem("Local fork", "localFork", sourceMode(), "managed", "For layer maintainers. Uses your local fork and warns about drift.")
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
        quickPickItem("Release", "release", channel(), "release", "Latest tagged, approved layer release."),
        quickPickItem("Edge", "edge", channel(), "release", "Current aproda branch. May contain unreleased changes."),
        quickPickItem("Pinned", "pinned", channel(), "release", "A specific tagged layer version.")
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

    const defaultBcqualityPath = normalizedRoot ? path.join(normalizedRoot, "BCQuality-Aproda") : "";
    const selectedBcqualityPath = await vscode.window.showInputBox({
        title: "Aproda ALDC: BCQuality Location",
        prompt: "Shared standalone BCQuality-Aproda repository. It must be outside project repositories.",
        value: bcqualityPath() || defaultBcqualityPath,
        ignoreFocusOut: true
    });
    if (selectedBcqualityPath === undefined) {
        return;
    }
    await updateGlobal("bcquality.path", selectedBcqualityPath.trim());

    const selectedStartupCheck = await vscode.window.showQuickPick([
        quickPickItem("Enable layer update checks", true, startupChecksEnabled(), true, "Checks for newer layers when an AL project opens."),
        quickPickItem("Disable layer update checks", false, startupChecksEnabled(), true, "Layer updates remain available from the Command Palette.")
    ], { title: "Aproda ALDC: Layer Update Checks", ignoreFocusOut: true });
    if (!selectedStartupCheck) {
        return;
    }
    await updateGlobal("startupCheck.enabled", selectedStartupCheck.value);
    if (selectedStartupCheck.value) {
        const interval = await vscode.window.showInputBox({
            title: "Aproda ALDC: Update Check Interval",
            prompt: "Minimum number of hours between automatic layer update checks.",
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

function quickPickItem<T>(label: string, value: T, current: T, defaultValue: T, description: string): vscode.QuickPickItem & { value: T } {
    const state = current === defaultValue ? "Default, Current" : current === value ? "Current" : value === defaultValue ? "Default" : "";
    return { label: state ? `${label} (${state})` : label, value, description, picked: current === value };
}