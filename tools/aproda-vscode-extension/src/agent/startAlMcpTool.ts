import * as vscode from "vscode";
import { resolveAldcRepository } from "../env/gitRoot";
import { Logger } from "../log";
import { StartRequestTarget, controlAlMcp } from "../alMcp/control";

const toolName = "aprodaAldc_startAlMcp";

export interface StartAlMcpInput {
    readonly action: "start" | "restart";
}

export function registerStartAlMcpTool(context: vscode.ExtensionContext, provider: StartRequestTarget, logger: Logger): void {
    context.subscriptions.push(vscode.lm.registerTool(toolName, new StartAlMcpTool(provider, logger)));
}

class StartAlMcpTool implements vscode.LanguageModelTool<StartAlMcpInput> {
    constructor(private readonly provider: StartRequestTarget, private readonly logger: Logger) { }

    async prepareInvocation(options: vscode.LanguageModelToolInvocationPrepareOptions<StartAlMcpInput>): Promise<vscode.PreparedToolInvocation> {
        const resolution = await resolveAldcRepository();
        const repository = resolution.state === "configured" ? resolution.repositoryRoot : "the open workspace";
        const verb = options.input?.action === "restart" ? "Restart" : "Start";
        return {
            invocationMessage: `${verb} the AL MCP server`,
            confirmationMessages: {
                title: `${verb} AL MCP Server`,
                message: `${verb} the AL MCP server for ${repository}?`
            }
        };
    }

    async invoke(options: vscode.LanguageModelToolInvocationOptions<StartAlMcpInput>, _token: vscode.CancellationToken): Promise<vscode.LanguageModelToolResult> {
        // Only `action` is read: a server id (or anything else) in the input is ignored.
        const action = options.input?.action;
        const result = action === "start" || action === "restart"
            ? await controlAlMcp(action, this.provider, this.logger)
            : { state: "failed", server: "al-mcp", message: "action must be 'start' or 'restart'." };
        return new vscode.LanguageModelToolResult([new vscode.LanguageModelTextPart(JSON.stringify(result, undefined, 2))]);
    }
}
