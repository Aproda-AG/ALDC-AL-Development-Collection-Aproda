import * as fs from "fs/promises";
import YAML from "yaml";
import { AldcRepositoryResolution } from "../env/gitRoot";

export const defaultEntryPoint = "skills/entry.md";

export interface BcqualityAldcConfig {
    readonly enabled: "auto" | boolean;
    readonly home?: string;
    readonly entryPoint: string;
}

// Shared by the resolver and the agent configuration tool so both read external.bcquality the same way.
export async function readBcqualityAldcConfig(resolution: AldcRepositoryResolution): Promise<BcqualityAldcConfig | undefined> {
    if (resolution.state !== "configured") {
        return undefined;
    }
    try {
        const document = YAML.parse(await fs.readFile(resolution.configurationPath, "utf8"));
        const external = isRecord(document) ? document.external : undefined;
        const bcquality = isRecord(external) ? external.bcquality : undefined;
        if (!isRecord(bcquality)) {
            return undefined;
        }
        return {
            enabled: normalizeEnabled(bcquality.enabled),
            home: typeof bcquality.home === "string" ? bcquality.home : undefined,
            entryPoint: typeof bcquality.entryPoint === "string" ? bcquality.entryPoint : defaultEntryPoint
        };
    } catch {
        return undefined;
    }
}

function normalizeEnabled(value: unknown): "auto" | boolean {
    if (value === true || value === false) {
        return value;
    }
    if (typeof value === "string") {
        if (value.toLowerCase() === "true") {
            return true;
        }
        if (value.toLowerCase() === "false") {
            return false;
        }
    }
    return "auto";
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
