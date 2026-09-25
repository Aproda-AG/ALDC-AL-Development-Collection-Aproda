import * as vscode from "vscode";
import { resolveBcquality } from "../bcquality/resolve";

const statusBarCommand = "aprodaAldc.showBcQualityStatus";

// The only permanently visible proof the knowledge layer is live (E-006 §1.3). Refreshed on demand from
// events the extension already listens to elsewhere -- never on a timer.
export class BcqualityStatusBar implements vscode.Disposable {
    private readonly item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 90);

    constructor() {
        this.item.command = statusBarCommand;
        this.item.text = "$(circle-slash) BCQuality";
        this.item.tooltip = "BCQuality status not checked yet. Click to check.";
    }

    async refresh(): Promise<void> {
        const resolution = await resolveBcquality();
        if (resolution.enabled === false) {
            this.item.text = "$(circle-slash) BCQuality";
            this.item.tooltip = "BCQuality is disabled for this project (external.bcquality.enabled: false). Click for details.";
            return;
        }
        if (resolution.verified && resolution.root) {
            this.item.text = "$(check) BCQuality";
            this.item.tooltip = new vscode.MarkdownString(
                `**BCQuality is active**\n\nResolved from \`${resolution.resolvedFrom}\`:\n\n\`${resolution.root}\`\n\nClick for the full resolver chain.`
            );
            return;
        }
        this.item.text = "$(circle-slash) BCQuality";
        this.item.tooltip = "BCQuality could not be resolved. Click for details and to install/update it.";
    }

    setVisible(visible: boolean): void {
        if (visible) {
            this.item.show();
        } else {
            this.item.hide();
        }
    }

    dispose(): void {
        this.item.dispose();
    }
}
