import * as vscode from "vscode";
import { registerStartAlMcpTool } from "../agent/startAlMcpTool";
import { alMcpStartMode } from "../config";
import { Logger } from "../log";
import { isAlWorkspace } from "../workspace/alWorkspace";
import { controlAlMcp } from "./control";
import { storeAlCredential } from "./credential";
import { registerDebugHint } from "./debugHint";
import { AlMcpProvider, providerId } from "./provider";
import { selectAlTarget } from "./selectTarget";
import { startOwnServer } from "./serverCommands";

// Spec §4.3a, `auto`: in an AL workspace the extension starts its own server once, so the tools exist before the
// first chat message. Leaving auto mode or the AL workspace re-arms it. If the start command is unavailable, VS Code's
// own autostart pass on the first chat message remains the start path.
export class AlMcpAutoStart {
    private started = false;

    constructor(private readonly provider: AlMcpProvider, private readonly logger: Logger) { }

    async evaluate(): Promise<void> {
        try {
            if (!isAlWorkspace() || alMcpStartMode() !== "auto") {
                this.started = false;
                return;
            }
            if (this.started) {
                return;
            }
            // Only start what VS Code can know about: no repository or no starter means no definition.
            const definitions = await this.provider.provideMcpServerDefinitions();
            if (definitions.length === 0 || this.started) {
                return;
            }
            this.started = true;
            this.provider.refreshNow();
            await startOwnServer(this.logger);
        } catch (error) {
            this.logger.error(`AL MCP auto start failed: ${error instanceof Error ? error.message : String(error)}`);
        }
    }
}

async function runControlCommand(action: "start" | "restart", provider: AlMcpProvider, logger: Logger): Promise<void> {
    const result = await controlAlMcp(action, provider, logger);
    if (result.state === "failed" || result.state === "notAlWorkspace") {
        void vscode.window.showWarningMessage(result.message);
    } else {
        void vscode.window.showInformationMessage(result.message);
    }
}

export function registerAlMcp(context: vscode.ExtensionContext, logger: Logger): AlMcpProvider {
    const provider = new AlMcpProvider(logger);
    const autoStart = new AlMcpAutoStart(provider, logger);
    context.subscriptions.push(
        provider,
        vscode.lm.registerMcpServerDefinitionProvider(providerId, provider),
        vscode.commands.registerCommand("aprodaAldc.selectAlTarget", () => selectAlTarget(logger)),
        vscode.commands.registerCommand("aprodaAldc.startAlMcp", () => runControlCommand("start", provider, logger)),
        vscode.commands.registerCommand("aprodaAldc.restartAlMcp", () => runControlCommand("restart", provider, logger)),
        vscode.commands.registerCommand("aprodaAldc.storeAlCredential", () => storeAlCredential(logger)),
        vscode.workspace.onDidChangeWorkspaceFolders(() => void autoStart.evaluate()),
        vscode.workspace.onDidChangeConfiguration((event) => {
            if (event.affectsConfiguration("aprodaAldc.alMcp.start")) {
                void autoStart.evaluate();
            }
        }),
        // Also covers aldc.yaml / the starter appearing after "Apply Toolkit to Project".
        provider.onDidChangeMcpServerDefinitions(() => void autoStart.evaluate())
    );
    registerStartAlMcpTool(context, provider, logger);
    registerDebugHint(context, logger);
    void autoStart.evaluate();
    return provider;
}
