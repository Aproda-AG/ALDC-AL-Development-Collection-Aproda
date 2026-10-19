// TypeScript port of skills/skill-aproda-al-mcp/scripts/AprodaAlTarget.ps1 (E-010 spec §2.2/§2.3).
// One rule set, two implementations: states, resolvedLaunch values and issue codes must stay identical
// to the PowerShell library; tests/fixtures/al-target/case-* is the shared parity gate.
import * as fs from "fs";
import * as path from "path";
import { parseTree, printParseErrorCode, type Node, type ParseError, type ParseOptions } from "jsonc-parser";

export type SelectionState = "noToolkit" | "absent" | "invalid" | "stale" | "configured";

export interface LaunchIssue {
    readonly code: string;
    readonly message: string;
}

export interface ResolvedLaunch {
    readonly name: string;
    readonly server: string;
    readonly scheme: string | null;
    readonly host: string | null;
    readonly serverInstance: string | null;
    readonly port: number | null;
    readonly portSource: "launch" | "default";
    readonly tenant: string;
    readonly environmentType: string;
    readonly authentication: string | null;
    readonly dependencyPublishingOption: string;
    readonly credentialKey: string | null;
}

export interface LocalSelection {
    readonly state: SelectionState;
    readonly path: string | null;
    readonly reason: string | null;
    readonly target: { readonly launchProject: string; readonly launchConfig: string } | null;
    readonly resolvedLaunch: ResolvedLaunch | null;
    readonly issues: readonly LaunchIssue[];
}

export interface TargetBundle {
    readonly serverUrl: string;
    readonly serverInstance: string;
    readonly port: number;
    readonly authentication: string;
    readonly tenant: string;
}

export interface LaunchConfigurationInfo {
    readonly launchProject: string;
    readonly name: string;
    readonly server: string;
    readonly serverInstance: string | null;
    readonly authentication: string | null;
    readonly issues: readonly LaunchIssue[];
}

// A JSON number is only an integer for the PowerShell rules when its literal has no fraction/exponent
// (ConvertFrom-Json yields a double for `7049.0`); JSON.parse cannot tell, so the literal is kept.
class NonIntegerNumber {
    constructor(readonly literal: string) { }
}

type JsonValue = string | number | boolean | null | NonIntegerNumber | JsonValue[] | JsonObject;
interface JsonObject { [key: string]: JsonValue }

const strictOptions: ParseOptions = { disallowComments: true, allowTrailingComma: false, allowEmptyContent: false };
const lenientOptions: ParseOptions = { disallowComments: false, allowTrailingComma: true, allowEmptyContent: false };

function readTextFile(filePath: string): string {
    const buffer = fs.readFileSync(filePath);
    if (buffer.length >= 2 && buffer[0] === 0xff && buffer[1] === 0xfe) {
        return buffer.subarray(2).toString("utf16le");
    }
    const text = buffer.toString("utf8");
    return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

function isObject(value: unknown): value is JsonObject {
    return typeof value === "object" && value !== null && !Array.isArray(value) && !(value instanceof NonIntegerNumber);
}

function getProperty(object: unknown, name: string): JsonValue | undefined {
    return isObject(object) && Object.hasOwn(object, name) ? object[name] : undefined;
}

function nodeToValue(node: Node, text: string): JsonValue {
    switch (node.type) {
        case "object": {
            const result: JsonObject = Object.create(null);
            for (const property of node.children ?? []) {
                const [key, value] = property.children ?? [];
                if (key && value) {
                    result[String(key.value)] = nodeToValue(value, text);
                }
            }
            return result;
        }
        case "array":
            return (node.children ?? []).map((child) => nodeToValue(child, text));
        case "number": {
            const literal = text.substring(node.offset, node.offset + node.length);
            return /^-?\d+$/.test(literal) && Number.isSafeInteger(node.value) ? (node.value as number) : new NonIntegerNumber(literal);
        }
        case "string":
        case "boolean":
            return node.value as string | boolean;
        default:
            return null;
    }
}

function parseDocument(text: string, options: ParseOptions): { ok: true; value: JsonValue } | { ok: false; reason: string } {
    const errors: ParseError[] = [];
    const tree = parseTree(text, errors, options);
    if (errors.length > 0 || !tree) {
        return { ok: false, reason: errors.length > 0 ? printParseErrorCode(errors[0].error) : "empty document" };
    }
    return { ok: true, value: nodeToValue(tree, text) };
}

// Strict JSON as System.Text.Json parses it by default: no comments, no trailing commas.
function parseStrictJson(text: string): { ok: true; value: JsonValue } | { ok: false; reason: string } {
    try {
        JSON.parse(text);
    } catch (error) {
        return { ok: false, reason: error instanceof Error ? error.message : String(error) };
    }
    return parseDocument(text, strictOptions);
}

function psString(value: JsonValue | undefined): string {
    if (value === undefined || value === null) {
        return "";
    }
    if (typeof value === "string") {
        return value;
    }
    if (typeof value === "boolean") {
        return value ? "True" : "False";
    }
    if (value instanceof NonIntegerNumber) {
        return value.literal;
    }
    return typeof value === "number" ? String(value) : JSON.stringify(value);
}

function isBlank(value: string): boolean {
    return value.trim().length === 0;
}

function isNonBlankString(value: JsonValue | undefined): value is string {
    return typeof value === "string" && !isBlank(value);
}

interface LaunchFile {
    readonly ok: boolean;
    readonly reason: string | null;
    readonly configurations: readonly JsonValue[];
}

function readLaunchFile(filePath: string): LaunchFile {
    if (!fileExists(filePath)) {
        return { ok: false, reason: `launch.json not found: ${filePath}`, configurations: [] };
    }
    let text: string;
    try {
        text = readTextFile(filePath);
    } catch (error) {
        return { ok: false, reason: `launch.json could not be read: ${filePath} (${error instanceof Error ? error.message : String(error)})`, configurations: [] };
    }
    const parsed = parseDocument(text, lenientOptions);
    if (!parsed.ok) {
        return { ok: false, reason: `launch.json could not be parsed: ${filePath} (${parsed.reason})`, configurations: [] };
    }
    const configurations = getProperty(parsed.value, "configurations");
    if (!Array.isArray(configurations)) {
        return { ok: false, reason: `launch.json has no 'configurations' array: ${filePath}`, configurations: [] };
    }
    return { ok: true, reason: null, configurations };
}

function fileExists(filePath: string): boolean {
    try {
        return fs.statSync(filePath).isFile();
    } catch {
        return false;
    }
}

function directoryExists(directoryPath: string): boolean {
    try {
        return fs.statSync(directoryPath).isDirectory();
    } catch {
        return false;
    }
}

function hasServer(configuration: JsonValue): boolean {
    return isNonBlankString(getProperty(configuration, "server"));
}

export function getLaunchFilePath(repositoryRoot: string, launchProject: string): string {
    const projectDirectory = path.join(repositoryRoot, launchProject.replace(/[\\/]/g, path.sep));
    return path.join(projectDirectory, ".vscode", "launch.json");
}

export function convertToResolvedLaunch(configuration: unknown, launchFilePath: string): { resolvedLaunch: ResolvedLaunch; issues: LaunchIssue[] } {
    const name = psString(getProperty(configuration, "name"));
    const issues: LaunchIssue[] = [];
    const addIssue = (code: string, text: string): void => {
        issues.push({ code, message: `${text} (configuration '${name}' in '${launchFilePath}')` });
    };

    let server = psString(getProperty(configuration, "server"));
    if (server.endsWith("/")) {
        server = server.slice(0, -1);
    }
    let scheme: string | null = null;
    let host: string | null = null;
    // .NET -match is case-insensitive by default.
    const serverMatch = /^(https?):\/\/([^/:?#@\s]+)$/i.exec(server);
    if (serverMatch) {
        scheme = serverMatch[1].toLowerCase();
        host = serverMatch[2];
    } else {
        addIssue("SERVER_INVALID", `server '${server}' must be an absolute http/https URL without path, query or port`);
    }

    const instanceValue = getProperty(configuration, "serverInstance");
    let serverInstance: string | null = null;
    if (isNonBlankString(instanceValue)) {
        serverInstance = instanceValue;
    } else {
        addIssue("INSTANCE_MISSING", "serverInstance is missing or empty");
    }

    const portValue = getProperty(configuration, "port");
    let port: number | null = null;
    let portSource: "launch" | "default" = "launch";
    if (portValue === undefined || portValue === null) {
        port = 7049;
        portSource = "default";
    } else if (typeof portValue === "number" && portValue >= 1 && portValue <= 65535) {
        port = portValue;
    } else {
        addIssue("PORT_INVALID", `port '${psString(portValue)}' must be an integer from 1 to 65535`);
    }

    const tenantValue = getProperty(configuration, "tenant");
    const tenant = isNonBlankString(tenantValue) ? tenantValue : "default";

    const environmentValue = getProperty(configuration, "environmentType");
    let environmentType = "OnPrem";
    if (environmentValue !== undefined && environmentValue !== null) {
        environmentType = psString(environmentValue);
        if (environmentType !== "OnPrem") {
            addIssue("NOT_ONPREM", `environmentType '${environmentType}' is not OnPrem`);
        }
    }

    const authenticationValue = getProperty(configuration, "authentication");
    let authentication: string | null = null;
    if (authenticationValue === undefined || authenticationValue === null || (typeof authenticationValue === "string" && isBlank(authenticationValue))) {
        addIssue("AUTH_MISSING", "authentication is not set; set it explicitly (Windows or UserPassword)");
    } else {
        const authenticationText = psString(authenticationValue);
        const lowered = authenticationText.toLowerCase();
        if (typeof authenticationValue !== "string") {
            authentication = authenticationText;
            addIssue("AUTH_UNKNOWN", `authentication '${authenticationText}' is not a known value`);
        } else if (lowered === "windows") {
            authentication = "Windows";
        } else if (lowered === "userpassword") {
            authentication = "UserPassword";
        } else if (lowered === "aad" || lowered === "microsoftentraid") {
            authentication = authenticationText;
            addIssue("AUTH_UNSUPPORTED", `authentication '${authenticationText}' is not supported yet (supported: Windows, UserPassword)`);
        } else {
            authentication = authenticationText;
            addIssue("AUTH_UNKNOWN", `authentication '${authenticationText}' is not a known value (supported: Windows, UserPassword)`);
        }
    }
    if (authentication === "UserPassword" && scheme === "http") {
        addIssue("USERPASSWORD_OVER_HTTP", "UserPassword is only allowed over https");
    }

    const dependencyValue = getProperty(configuration, "dependencyPublishingOption");
    let dependencyOption = "Default";
    if (dependencyValue !== undefined && dependencyValue !== null) {
        dependencyOption = psString(dependencyValue);
        if (!["Default", "Ignore", "Strict"].includes(dependencyOption)) {
            addIssue("DEPENDENCY_OPTION_INVALID", `dependencyPublishingOption '${dependencyOption}' must be Default, Ignore or Strict`);
        }
    }

    return {
        resolvedLaunch: {
            name,
            server,
            scheme,
            host,
            serverInstance,
            port,
            portSource,
            tenant,
            environmentType,
            authentication,
            dependencyPublishingOption: dependencyOption,
            credentialKey: host
        },
        issues
    };
}

interface TargetResolution {
    readonly state: "invalid" | "stale" | "configured";
    readonly reason: string | null;
    readonly resolvedLaunch: ResolvedLaunch | null;
    readonly issues: readonly LaunchIssue[];
}

export function resolveLaunchTarget(repositoryRoot: string, launchProject: unknown, launchConfig: unknown): TargetResolution {
    const fail = (state: "invalid" | "stale", reason: string): TargetResolution => ({ state, reason, resolvedLaunch: null, issues: [] });

    if (typeof launchProject !== "string" || isBlank(launchProject)) {
        return fail("invalid", "target.launchProject: must be a non-empty string");
    }
    if (typeof launchConfig !== "string" || isBlank(launchConfig)) {
        return fail("invalid", "target.launchConfig: must be a non-empty string");
    }
    if (/^[\\/]/.test(launchProject) || /^[A-Za-z]:/.test(launchProject) || path.win32.isAbsolute(launchProject)) {
        return fail("invalid", "target.launchProject: must be relative to the repository (rooted path not allowed)");
    }
    if (launchProject.split(/[\\/]/).includes("..")) {
        return fail("invalid", "target.launchProject: '..' segment not allowed");
    }

    const launchFilePath = getLaunchFilePath(repositoryRoot, launchProject);
    const launchFile = readLaunchFile(launchFilePath);
    if (!launchFile.ok) {
        return fail("stale", launchFile.reason ?? "launch.json is not usable");
    }
    const match = launchFile.configurations.find((candidate) => {
        const candidateName = getProperty(candidate, "name");
        return typeof candidateName === "string" && candidateName === launchConfig;
    });
    if (match === undefined) {
        return fail("stale", `launch.json has no configuration named '${launchConfig}': ${launchFilePath}`);
    }
    if (!hasServer(match)) {
        return fail("stale", `configuration '${launchConfig}' has no server: ${launchFilePath}`);
    }
    const derived = convertToResolvedLaunch(match, launchFilePath);
    return { state: "configured", reason: null, resolvedLaunch: derived.resolvedLaunch, issues: derived.issues };
}

export function getLocalSelectionPath(repositoryRoot: string): string | null {
    const githubConfig = path.join(repositoryRoot, ".github", "aldc.yaml");
    if (fileExists(githubConfig)) {
        return path.join(repositoryRoot, ".github", "aldc.local.json");
    }
    if (fileExists(path.join(repositoryRoot, "aldc.yaml"))) {
        return path.join(repositoryRoot, "aldc.local.json");
    }
    return null;
}

function selectionOf(state: SelectionState, selectionPath: string | null, reason: string | null = null, extra: Partial<Pick<LocalSelection, "target" | "resolvedLaunch" | "issues">> = {}): LocalSelection {
    return {
        state,
        path: selectionPath,
        reason,
        target: extra.target ?? null,
        resolvedLaunch: extra.resolvedLaunch ?? null,
        issues: extra.issues ?? []
    };
}

export function getLocalSelection(repositoryRoot: string): LocalSelection {
    const selectionPath = getLocalSelectionPath(repositoryRoot);
    if (selectionPath === null) {
        return selectionOf("noToolkit", null, "no aldc.yaml found under the repository root");
    }
    if (!fileExists(selectionPath)) {
        return selectionOf("absent", selectionPath);
    }

    let text: string;
    try {
        text = readTextFile(selectionPath);
    } catch (error) {
        return selectionOf("invalid", selectionPath, `file: unreadable (${error instanceof Error ? error.message : String(error)})`);
    }
    const parsed = parseStrictJson(text);
    if (!parsed.ok) {
        return selectionOf("invalid", selectionPath, `file: not strict JSON (${parsed.reason})`);
    }
    const document = parsed.value;
    if (!isObject(document)) {
        return selectionOf("invalid", selectionPath, "root: must be a JSON object");
    }
    if (getProperty(document, "version") !== 1) {
        return selectionOf("invalid", selectionPath, "version: must be the integer 1");
    }
    const target = getProperty(document, "target");
    if (!isObject(target)) {
        return selectionOf("invalid", selectionPath, "target: must be an object");
    }
    const launchProject = getProperty(target, "launchProject");
    const launchConfig = getProperty(target, "launchConfig");

    const resolution = resolveLaunchTarget(repositoryRoot, launchProject, launchConfig);
    if (resolution.state === "invalid") {
        return selectionOf("invalid", selectionPath, resolution.reason);
    }
    return selectionOf(resolution.state, selectionPath, resolution.reason, {
        target: { launchProject: launchProject as string, launchConfig: launchConfig as string },
        resolvedLaunch: resolution.resolvedLaunch,
        issues: resolution.issues
    });
}

// Atomic write (temp file + rename), UTF-8 without BOM, 2-space indent, LF, trailing newline; unknown keys preserved.
function saveLocalSelectionFile(filePath: string, launchProject: string, launchConfig: string): void {
    let existing: JsonObject | undefined;
    if (fileExists(filePath)) {
        const parsed = parseStrictJson(readTextFile(filePath));
        if (parsed.ok && isObject(parsed.value)) {
            existing = parsed.value;
        }
    }

    const target: JsonObject = Object.create(null);
    target.launchProject = launchProject;
    target.launchConfig = launchConfig;
    const existingTarget = existing ? getProperty(existing, "target") : undefined;
    if (isObject(existingTarget)) {
        for (const [key, value] of Object.entries(existingTarget)) {
            if (key !== "launchProject" && key !== "launchConfig") {
                target[key] = value;
            }
        }
    }
    const document: JsonObject = Object.create(null);
    document.version = 1;
    document.target = target;
    if (existing) {
        for (const [key, value] of Object.entries(existing)) {
            if (key !== "version" && key !== "target") {
                document[key] = value;
            }
        }
    }

    const json = `${JSON.stringify(document, jsonReplacer, 2)}\n`;
    const temporaryPath = `${filePath}.tmp`;
    try {
        fs.writeFileSync(temporaryPath, json, { encoding: "utf8" });
        fs.renameSync(temporaryPath, filePath);
    } catch (error) {
        fs.rmSync(temporaryPath, { force: true });
        throw error;
    }
}

function jsonReplacer(_key: string, value: unknown): unknown {
    return value instanceof NonIntegerNumber ? Number(value.literal) : value;
}

export function setLocalSelection(repositoryRoot: string, launchProject: string, launchConfig: string): LocalSelection {
    const selectionPath = getLocalSelectionPath(repositoryRoot);
    if (selectionPath === null) {
        throw new Error("SELECTION_WOULD_BE_NOTOOLKIT: no aldc.yaml found under the repository root");
    }
    const resolution = resolveLaunchTarget(repositoryRoot, launchProject, launchConfig);
    if (resolution.state !== "configured") {
        throw new Error(`SELECTION_WOULD_BE_${resolution.state.toUpperCase()}: ${resolution.reason}`);
    }
    saveLocalSelectionFile(selectionPath, launchProject, launchConfig);
    return getLocalSelection(repositoryRoot);
}

// Direct sub-folders of the repository root that contain app.json, ordinal-sorted (C-8).
export function getAlProjects(repositoryRoot: string): { name: string; path: string }[] {
    if (!directoryExists(repositoryRoot)) {
        return [];
    }
    const names: string[] = [];
    for (const entry of fs.readdirSync(repositoryRoot)) {
        const projectPath = path.join(repositoryRoot, entry);
        if (directoryExists(projectPath) && fileExists(path.join(projectPath, "app.json"))) {
            names.push(entry);
        }
    }
    // Default sort compares UTF-16 code units, which is the ordinal order of the PowerShell library.
    names.sort();
    return names.map((name) => ({ name, path: path.join(repositoryRoot, name) }));
}

export function getLaunchConfigurations(repositoryRoot: string): LaunchConfigurationInfo[] {
    const result: LaunchConfigurationInfo[] = [];
    for (const project of getAlProjects(repositoryRoot)) {
        const launchFilePath = path.join(project.path, ".vscode", "launch.json");
        const launchFile = readLaunchFile(launchFilePath);
        if (!launchFile.ok) {
            continue;
        }
        for (const configuration of launchFile.configurations) {
            if (!hasServer(configuration)) {
                continue;
            }
            const authentication = getProperty(configuration, "authentication");
            const serverInstance = getProperty(configuration, "serverInstance");
            result.push({
                launchProject: project.name,
                name: psString(getProperty(configuration, "name")),
                server: psString(getProperty(configuration, "server")),
                serverInstance: serverInstance === undefined || serverInstance === null ? null : psString(serverInstance),
                authentication: authentication === undefined || authentication === null ? null : psString(authentication),
                issues: convertToResolvedLaunch(configuration, launchFilePath).issues
            });
        }
    }
    return result;
}

export function getTargetBundle(selection: LocalSelection | null | undefined): TargetBundle {
    if (!selection || selection.state !== "configured") {
        throw new Error(`TARGET_NOT_CONFIGURED: the AL target selection is '${selection ? selection.state : "none"}'`);
    }
    if (selection.issues.length > 0) {
        throw new Error(`TARGET_BLOCKED: ${selection.issues.map((issue) => issue.code).join(",")}`);
    }
    const resolved = selection.resolvedLaunch!;
    return {
        serverUrl: `${resolved.scheme}://${resolved.host}`,
        serverInstance: resolved.serverInstance!,
        port: resolved.port!,
        authentication: resolved.authentication!,
        tenant: resolved.tenant
    };
}

export function tryGetTargetBundle(selection: LocalSelection): TargetBundle | undefined {
    return selection.state === "configured" && selection.issues.length === 0 ? getTargetBundle(selection) : undefined;
}

// The subset of resolvedLaunch that `#aldcConfiguration` exposes (spec §4.6): never secrets, no credential state.
export const localResolvedLaunchFields = [
    "name", "server", "serverInstance", "port", "portSource", "tenant", "environmentType", "authentication", "dependencyPublishingOption"
] as const;

export function toLocalBlock(selection: LocalSelection): Record<string, unknown> {
    let resolvedLaunch: Record<string, unknown> | undefined;
    if (selection.state === "configured" && selection.resolvedLaunch) {
        resolvedLaunch = {};
        for (const field of localResolvedLaunchFields) {
            resolvedLaunch[field] = selection.resolvedLaunch[field];
        }
    }
    return {
        state: selection.state,
        path: selection.path,
        reason: selection.reason,
        target: selection.target,
        resolvedLaunch,
        targetBundle: tryGetTargetBundle(selection),
        issues: selection.issues
    };
}
