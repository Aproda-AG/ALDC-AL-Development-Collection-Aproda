import { autoReconcileBcquality, ExternalMount, externalMount } from "../config";
import { resolveAldcRepository } from "../env/gitRoot";
import { isExternalProviderRegistered } from "./externalFileSystemProvider";
import { JunctionState, junctionPath, junctionState, WorkspaceRootForm, workspaceRootForm } from "./mountState";

export interface ExternalFinding {
    readonly level: "info" | "warning";
    readonly message: string;
}

export interface ExternalFindingInput {
    readonly rootForm: WorkspaceRootForm;
    readonly autoReconcile: boolean;
    readonly mount: ExternalMount;
    readonly junction: JunctionState;
    readonly junctionPath?: string;
}

// Pure so the three warnings are testable without a window.
export function buildExternalFindings(input: ExternalFindingInput): ExternalFinding[] {
    const findings: ExternalFinding[] = [];
    if (input.rootForm === "path" && !input.autoReconcile) {
        findings.push({
            level: "warning",
            message: "The workspace file lists the .external folder as a path and aprodaAldc.bcquality.autoReconcile is off, so it will not be migrated to the aldc-external:/ virtual root. Re-enable autoReconcile or change the folder entry by hand."
        });
    }
    if (input.junction !== "absent" && input.mount !== "junction") {
        findings.push({
            level: "warning",
            message: `A .external/bcquality junction exists while aprodaAldc.external.mount is "${input.mount}". It is not needed; remove it with: cmd /c rmdir "${input.junctionPath ?? ".external\\bcquality"}"`
        });
    }
    if (input.junction === "unreadable") {
        findings.push({
            level: "warning",
            message: `The .external/bcquality junction cannot be read. Junctions on network drives do not work (E-006 e2e-05). Remove it with: cmd /c rmdir "${input.junctionPath ?? ".external\\bcquality"}"`
        });
    }
    return findings;
}

export async function collectExternalFindings(): Promise<ExternalFinding[]> {
    const repository = await resolveAldcRepository();
    const repositoryRoot = repository.state === "configured" ? repository.repositoryRoot : undefined;
    const findings = buildExternalFindings({
        rootForm: await workspaceRootForm(),
        autoReconcile: autoReconcileBcquality(),
        mount: externalMount(),
        junction: repositoryRoot ? await junctionState(repositoryRoot) : "absent",
        junctionPath: repositoryRoot ? junctionPath(repositoryRoot) : undefined
    });
    findings.unshift({ level: "info", message: `External mount: ${externalMount()}; aldc-external provider ${isExternalProviderRegistered() ? "registered" : "not registered"}.` });
    return findings;
}
