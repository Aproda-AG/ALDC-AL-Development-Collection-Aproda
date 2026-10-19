import * as vscode from "vscode";
import { resolveAldcRepository } from "../env/gitRoot";
import { Logger } from "../log";
import { LaunchConfigurationInfo, getLaunchConfigurations, setLocalSelection } from "./localSelection";

export interface TargetPickItem extends vscode.QuickPickItem {
    readonly config: LaunchConfigurationInfo;
}

export function buildTargetItems(configurations: readonly LaunchConfigurationInfo[]): TargetPickItem[] {
    return configurations.map((config) => {
        const codes = config.issues.map((issue) => issue.code);
        return {
            label: config.name,
            description: `${config.server}/${config.serverInstance ?? ""}`,
            detail: `${config.authentication ?? "authentication missing"} · ${config.launchProject}${codes.length > 0 ? ` · blocked: ${codes.join(", ")}` : ""}`,
            config
        };
    });
}

// createQuickPick instead of showQuickPick: an item with blocking issues must stay unselectable, which
// showQuickPick cannot express.
function pickTarget(items: TargetPickItem[]): Promise<TargetPickItem | undefined> {
    return new Promise((resolve) => {
        const quickPick = vscode.window.createQuickPick<TargetPickItem>();
        quickPick.title = "Select AL target";
        quickPick.placeholder = "Choose the launch.json configuration used for AL MCP and deployment";
        quickPick.matchOnDescription = true;
        quickPick.matchOnDetail = true;
        quickPick.items = items;
        let settled = false;
        quickPick.onDidAccept(() => {
            const picked = quickPick.selectedItems[0];
            if (!picked) {
                return;
            }
            if (picked.config.issues.length > 0) {
                quickPick.placeholder = `'${picked.config.name}' is blocked (${picked.config.issues.map((issue) => issue.code).join(", ")}); fix launch.json or pick another`;
                return;
            }
            settled = true;
            resolve(picked);
            quickPick.hide();
        });
        quickPick.onDidHide(() => {
            if (!settled) {
                resolve(undefined);
            }
            quickPick.dispose();
        });
        quickPick.show();
    });
}

export async function applyTargetSelection(repositoryRoot: string, launchProject: string, launchConfig: string, logger: Logger): Promise<boolean> {
    try {
        setLocalSelection(repositoryRoot, launchProject, launchConfig);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.error(`AL target selection refused: ${message}`);
        void vscode.window.showErrorMessage(`AL target not changed: ${message}`);
        return false;
    }
    logger.info(`AL target selected: ${launchProject} / ${launchConfig}.`);
    void vscode.window.showInformationMessage("Target selected. Deploying still needs the environment confirmation in chat.");
    return true;
}

export async function selectAlTarget(logger: Logger): Promise<boolean> {
    const resolution = await resolveAldcRepository();
    if (resolution.state !== "configured") {
        void vscode.window.showWarningMessage("No ALDC repository found for the open workspace; apply the toolkit before selecting an AL target.");
        return false;
    }
    const configurations = getLaunchConfigurations(resolution.repositoryRoot);
    if (configurations.length === 0) {
        void vscode.window.showWarningMessage("No AL launch configuration with a server was found in any project's .vscode/launch.json.");
        return false;
    }
    const picked = await pickTarget(buildTargetItems(configurations));
    if (!picked) {
        return false;
    }
    return applyTargetSelection(resolution.repositoryRoot, picked.config.launchProject, picked.config.name, logger);
}
