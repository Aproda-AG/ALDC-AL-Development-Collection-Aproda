import * as vscode from "vscode";
import * as fs from "fs";
import { extensionUpdateChecksEnabled, startupCheckIntervalHours, startupChecksEnabled } from "./config";
import { resetLocalData } from "./commands/resetData";
import { checkForLayerUpdates, markStartupCheckComplete, shouldRunStartupCheck } from "./startup/check";
import { Logger } from "./log";
import { initializeProject } from "./commands/initProject";
import { LayerSource } from "./source/layerSource";
import { asMessage, runDoctor } from "./setup/doctor";
import { offerInitialSetup, runSetupWizard } from "./setup/wizard";
import { registerReadAldcConfigurationTool } from "./agent/readAldcConfigurationTool";
import { installOrUpdateBcquality } from "./bcquality/install";
import { resolveTargetRepo } from "./env/gitRoot";
import { reconcileBcqualityWorkspace } from "./workspace/bcqualityRoot";
import { openGettingStarted, openWalkthrough } from "./commands/gettingStarted";
import { validateInstallation } from "./commands/validate";
import { checkForExtensionUpdates, shouldRunExtensionUpdateCheck } from "./commands/extensionUpdate";
import { hasInitializedAlProject, offerRepositoryInitialization } from "./startup/repositoryInitialization";

export function activate(context: vscode.ExtensionContext): void {
  const logger = new Logger();
  const layerSource = new LayerSource(context, logger);
  let startupCheck: Promise<void> | undefined;
  context.subscriptions.push(logger);
  registerReadAldcConfigurationTool(context);

  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.showLog", () => logger.show()));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.doctor", () => runDoctor(context, logger, layerSource)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.setup", async () => {
    if (await runSetupWizard(context, logger, layerSource)) {
      await offerRepositoryInitialization(context, logger, layerSource);
    }
  }));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.initProject", () => initializeProject(layerSource, logger, false)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.previewChanges", () => initializeProject(layerSource, logger, true)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.checkForUpdates", () => checkForLayerUpdates(context, logger, true)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.checkExtensionUpdates", () => checkForExtensionUpdates(context, logger, true)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.installBcQuality", async () => {
    const bcqualityRoot = await installOrUpdateBcquality(logger);
    const repositoryRoot = await resolveTargetRepo();
    if (bcqualityRoot && repositoryRoot) {
      await reconcileBcqualityWorkspace(repositoryRoot, bcqualityRoot, logger);
    }
  }));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.openWalkthrough", () => openWalkthrough()));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.gettingStarted", () => openGettingStarted()));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.validate", () => validateInstallation(logger)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.resetData", () => resetLocalData(context, layerSource, logger, () => startupCheck)));
  context.subscriptions.push(vscode.commands.registerCommand("aprodaAldc.repairCache", async () => {
    try {
      await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: "Repairing Aproda ALDC toolkit cache" }, () => layerSource.repair());
      void vscode.window.showInformationMessage("Aproda ALDC toolkit cache is ready.");
    } catch (error) {
      logger.error(asMessage(error));
      void vscode.window.showErrorMessage(`Aproda ALDC cache repair failed: ${asMessage(error)}`, "Show Log").then((selection) => {
        if (selection === "Show Log") {
          logger.show();
        }
      });
    }
  }));

  logger.info("Aproda ALDC extension activated.");
  void startWorkspaceLifecycle();
  if (extensionUpdateChecksEnabled() && shouldRunExtensionUpdateCheck(context, startupCheckIntervalHours())) {
    void checkForExtensionUpdates(context, logger, false);
  }

  async function startWorkspaceLifecycle(): Promise<void> {
    const isAlProject = isAlWorkspace();
    const isInitializedProject = await hasInitializedAlProject();
    await vscode.commands.executeCommand("setContext", "aprodaAldc.isAlProject", isAlProject);
    const setupCompleted = await offerInitialSetup(context);
    if (!setupCompleted) {
      return;
    }
    if (isAlProject && !isInitializedProject) {
      await offerRepositoryInitialization(context, logger, layerSource);
      return;
    }
    if (isInitializedProject && startupChecksEnabled() && shouldRunStartupCheck(context, startupCheckIntervalHours())) {
      startupCheck = checkForLayerUpdates(context, logger, false).finally(() => markStartupCheckComplete(context));
    }
  }
}

function isAlWorkspace(): boolean {
  return vscode.workspace.workspaceFolders?.some((folder) => fs.existsSync(vscode.Uri.joinPath(folder.uri, "app.json").fsPath)) ?? false;
}

export function deactivate(): void {
  // VS Code disposes subscriptions registered by activate.
}
