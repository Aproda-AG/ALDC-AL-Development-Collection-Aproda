import * as fs from "fs";
import * as vscode from "vscode";
import YAML from "yaml";
import { resolveAldcRepository } from "../env/gitRoot";

const toolName = "aprodaAldc_readConfiguration";

type ConfigurationRecord = Record<string, unknown>;

export function registerReadAldcConfigurationTool(context: vscode.ExtensionContext): void {
    context.subscriptions.push(vscode.lm.registerTool(toolName, new ReadAldcConfigurationTool()));
}

class ReadAldcConfigurationTool implements vscode.LanguageModelTool<Record<string, never>> {
    async prepareInvocation(): Promise<vscode.PreparedToolInvocation> {
        return { invocationMessage: "Reading the ALDC configuration" };
    }

    async invoke(
        _options: vscode.LanguageModelToolInvocationOptions<Record<string, never>>,
        _token: vscode.CancellationToken
    ): Promise<vscode.LanguageModelToolResult> {
        const resolution = await resolveAldcRepository();
        if (resolution.state !== "configured") {
            return this.result(resolution);
        }

        try {
            const document = YAML.parse(fs.readFileSync(resolution.configurationPath, "utf8"));
            if (!isRecord(document)) {
                return this.result({
                    state: "invalidConfiguration",
                    repositoryRoot: resolution.repositoryRoot,
                    configurationPath: resolution.configurationPath,
                    message: "The file must contain a YAML mapping. Do not infer ALDC configuration values."
                });
            }

            const external = isRecord(document.external) ? document.external : undefined;
            const bcquality = external && isRecord(external.bcquality) ? external.bcquality : undefined;
            const plans = isRecord(document.plans) ? document.plans : undefined;
            const aproda = isRecord(document.aproda) ? document.aproda : undefined;

            return this.result({
                state: "configured",
                repositoryRoot: resolution.repositoryRoot,
                configurationPath: resolution.configurationPath,
                toolkitRoot: stringValue(document.toolkitRoot),
                copilotEntrypoint: stringValue(document.copilotEntrypoint),
                plansRoot: plans ? stringValue(plans.root) : undefined,
                layerVersion: aproda ? stringValue(aproda.layerVersion) : undefined,
                bcquality: bcquality ? {
                    enabled: bcquality.enabled,
                    home: stringValue(bcquality.home),
                    entryPoint: stringValue(bcquality.entryPoint),
                    url: stringValue(bcquality.url),
                    pinnedCommit: stringValue(bcquality.pinnedCommit),
                    pilotSkills: bcquality.pilotSkills
                } : undefined,
                guidance: "This is the authoritative configuration for the current ALDC repository. Use these values; do not guess missing values."
            });
        } catch (error) {
            return this.result({
                state: "invalidConfiguration",
                repositoryRoot: resolution.repositoryRoot,
                configurationPath: resolution.configurationPath,
                message: `Unable to parse aldc.yaml: ${error instanceof Error ? error.message : String(error)}`
            });
        }
    }

    private result(value: unknown): vscode.LanguageModelToolResult {
        return new vscode.LanguageModelToolResult([
            new vscode.LanguageModelTextPart(JSON.stringify(value, undefined, 2))
        ]);
    }
}

function isRecord(value: unknown): value is ConfigurationRecord {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
    return typeof value === "string" ? value : undefined;
}
