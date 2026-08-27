import * as vscode from "vscode";
import * as fs from "fs";
import { repositoryUrl, sourceMode, startupCheckIntervalHours, startupChecksEnabled, updateGlobal } from "./config";
import { resetLocalData } from "./commands/resetData";
import { checkForLayerUpdates, markStartupCheckComplete, shouldRunStartupCheck } from "./startup/check";
import { Logger } from "./log";
import { initializeProject } from "./commands/initProject";
import { LayerSource } from "./source/layerSource";
import { asMessage, runDoctor } from "./setup/doctor";

export function activate(context: vscode.ExtensionContext): void {
  const logger = new Logger();
  const layerSource = new LayerSource(context, logger);
  let startupCheck: Promise<void> | undefined;
  context.subscriptions.push(logger);

  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.showLog", () => logger.show()));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.doctor", () => runDoctor(context, logger, layerSource)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.setup", () => runSetup()));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.initProject", () => initializeProject(layerSource, logger, false)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.previewChanges", () => initializeProject(layerSource, logger, true)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.checkForUpdates", () => checkForLayerUpdates(context, logger, true)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.resetData", () => resetLocalData(context, layerSource, logger, () => startupCheck)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.repairCache", async () => {
    try {
      await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "Repairing Aproda ALDC layer cache" }, () => layerSource.repair());
      void vscode.window.showInformationMessage("Aproda ALDC layer cache is ready.");
    } catch (error) {
      logger.error(asMessage(error));
      void vscode.window.showErrorMessage(`Aproda ALDC cache repair failed: ${asMessage(error)}`, "Show Log").then((selection) => {
        if (selection === "Show Log") {
          logger.show();
        }
      });
    }
  }));

  const isAlProject = isAlWorkspace();
  void vscode.commands.executeCommand("setContext", "aprodaAldc.isAlProject", isAlProject);
  logger.info("Aproda ALDC extension activated.");
  if (isAlProject && startupChecksEnabled() && shouldRunStartupCheck(context, startupCheckIntervalHours())) {
    startupCheck = checkForLayerUpdates(context, logger, false).finally(() => markStartupCheckComplete(context));
  }
}

function isAlWorkspace(): boolean {
  return vscode.workspace.workspaceFolders?.some((folder) => fs.existsSync(vscode.Uri.joinPath(folder.uri, "app.json").fsPath)) ?? false;
}

async function runSetup(): Promise<void> {
  const currentMode = sourceMode();
  const selectedMode = await vscode.window.showQuickPick([
    { label: "Managed cache", value: "managed" as const, description: "Recommended. The extension maintains a clean local clone." },
    { label: "Local fork", value: "localFork" as const, description: "For Aproda layer maintainers." }
  ], { placeHolder: "Choose the Aproda ALDC layer source" });
  if (!selectedMode) {
    return;
  }

  await updateGlobal("source.mode", selectedMode.value);
  if (selectedMode.value === "localFork") {
    const selectedFolder = await vscode.window.showOpenDialog({ canSelectFiles: false, canSelectFolders: true, canSelectMany: false, openLabel: "Select Local Aproda Fork" });
    if (selectedFolder?.[0]) {
      await updateGlobal("source.forkPath", selectedFolder[0].fsPath);
    }
  }
  if (!repositoryUrl()) {
    await updateGlobal("source.repositoryUrl", "https://github.com/Aproda-AG/ALDC-AL-Development-Collection-Aproda.git");
  }
  if (currentMode !== selectedMode.value) {
    void vscode.window.showInformationMessage(`Aproda ALDC source mode changed to ${selectedMode.label}.`);
    return;
  }
  void vscode.window.showInformationMessage(`Aproda ALDC setup is complete. Layer source: ${selectedMode.label}.`);
}

export function deactivate(): void {
  // VS Code disposes subscriptions registered by activate.
}
