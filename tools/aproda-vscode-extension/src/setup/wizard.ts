import * as vscode from "vscode";
import * as path from "path";
import { bcqualityPath, Channel, channel, devRoot, forkPath, hasConfiguredValue, pinnedVersion, sourceMode, startupCheckIntervalHours, startupChecksEnabled, updateGlobal } from "../config";
import { directoryExists, proposeDevRoot } from "../env/devRoot";
import { resolveTargetRepo } from "../env/gitRoot";
import { Logger } from "../log";
import { runDoctor } from "./doctor";
import { LayerSource } from "../source/layerSource";

const setupCompletedKey = "setupCompleted";

export async function resetSetupState(context: vscode.ExtensionContext): Promise<void> {
    await context.globalState.update(setupCompletedKey, undefined);
}

export async function offerInitialSetup(context: vscode.ExtensionContext): Promise<boolean> {
    if (context.globalState.get<boolean>(setupCompletedKey)) {
        return true;
    }
    const choice = await vscode.window.showInformationMessage(
        "Welcome to Aproda ALDC. Open the guided setup to configure your environment and initialize a project.",
        "Open Get Started"
    );
    if (choice === "Open Get Started") {
        await vscode.commands.executeCommand("aprodaAldc.openWalkthrough");
    }
    return false;
}

export async function runSetupWizard(context: vscode.ExtensionContext, logger: Logger, layerSource: LayerSource): Promise<boolean> {
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
        return false;
    }
    const normalizedRoot = selectedRoot.trim();
    if (normalizedRoot && !await directoryExists(normalizedRoot)) {
        const choice = await vscode.window.showWarningMessage(`Developer root does not exist: ${normalizedRoot}`, "Use Anyway", "Cancel");
        if (choice !== "Use Anyway") {
            return false;
        }
    }
    await updateGlobal("devRoot", normalizedRoot);

    const configuredSourceMode = hasConfiguredValue("source.mode");
    const selectedMode = await vscode.window.showQuickPick([
        quickPickItem("Managed cache", "managed", sourceMode(), "managed", configuredSourceMode, "Keeps an extension-managed local copy of the approved toolkit release."),
        quickPickItem("Local fork", "localFork", sourceMode(), "managed", configuredSourceMode, "For toolkit maintainers. Uses your local fork and warns about drift.")
    ], { title: "Aproda ALDC: Toolkit Source", ignoreFocusOut: true });
    if (!selectedMode) {
        return false;
    }
    await updateGlobal("source.mode", selectedMode.value);
    if (selectedMode.value === "localFork" && !forkPath()) {
        const selectedFolder = await vscode.window.showOpenDialog({ canSelectFiles: false, canSelectFolders: true, canSelectMany: false, openLabel: "Select Local Aproda Fork" });
        if (!selectedFolder?.[0]) {
            return false;
        }
        await updateGlobal("source.forkPath", selectedFolder[0].fsPath);
    }

    const configuredChannel = hasConfiguredValue("channel");
    const selectedChannel = await vscode.window.showQuickPick([
        quickPickItem("Release", "release", channel(), "release", configuredChannel, "Latest tagged, approved toolkit release."),
        quickPickItem("Edge", "edge", channel(), "release", configuredChannel, "Current aproda branch. May contain unreleased changes."),
        quickPickItem("Pinned", "pinned", channel(), "release", configuredChannel, "A specific tagged toolkit version.")
    ], { title: "Aproda ALDC: Toolkit Channel", ignoreFocusOut: true });
    if (!selectedChannel) {
        return false;
    }
    await updateGlobal("channel", selectedChannel.value as Channel);
    if (selectedChannel.value === "pinned") {
        const version = await vscode.window.showInputBox({
            title: "Aproda ALDC: Pinned Toolkit Version",
            prompt: "Enter the toolkit version to use.",
            value: pinnedVersion(),
            validateInput: (value) => /^\d+\.\d+\.\d+_aproda\.\d+$/.test(value.trim()) ? undefined : "Enter a version such as 1.2.0_aproda.9.",
            ignoreFocusOut: true
        });
        if (version === undefined) {
            return false;
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
        return false;
    }
    await updateGlobal("bcquality.path", selectedBcqualityPath.trim());

    const configuredStartupCheck = hasConfiguredValue("startupCheck.enabled");
    const selectedStartupCheck = await vscode.window.showQuickPick([
        quickPickItem("Enable toolkit update checks", true, startupChecksEnabled(), true, configuredStartupCheck, "Checks for newer toolkits when an AL project opens."),
        quickPickItem("Disable toolkit update checks", false, startupChecksEnabled(), true, configuredStartupCheck, "Toolkit updates remain available from the Command Palette.")
    ], { title: "Aproda ALDC: Toolkit Update Checks", ignoreFocusOut: true });
    if (!selectedStartupCheck) {
        return false;
    }
    await updateGlobal("startupCheck.enabled", selectedStartupCheck.value);
    if (selectedStartupCheck.value) {
        const interval = await vscode.window.showInputBox({
            title: "Aproda ALDC: Update Check Interval",
            prompt: "Minimum number of hours between automatic toolkit update checks.",
            value: String(startupCheckIntervalHours()),
            validateInput: (value) => /^\d+$/.test(value) && Number(value) >= 1 ? undefined : "Enter a whole number of at least 1.",
            ignoreFocusOut: true
        });
        if (interval === undefined) {
            return false;
        }
        await updateGlobal("startupCheck.intervalHours", Number(interval));
    }
    await context.globalState.update(setupCompletedKey, true);
    logger.info("Aproda ALDC settings wizard completed.");
    void vscode.window.showInformationMessage("Aproda ALDC settings were saved.");
    return true;
}

function quickPickItem<T>(label: string, value: T, current: T, defaultValue: T, isConfigured: boolean, description: string): vscode.QuickPickItem & { value: T } {
    const state = [
        value === defaultValue ? "Default" : "",
        isConfigured && current === value ? "Current" : ""
    ].filter(Boolean).join(", ");
    return { label: state ? `${label} (${state})` : label, value, description, picked: current === value };
}