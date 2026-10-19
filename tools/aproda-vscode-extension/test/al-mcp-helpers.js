// Shared test helpers for the AL MCP tests: a programmable `vscode` mock (installed through Module._load, like the
// other extension tests) and a throw-away repository builder. Tests run against dist/.
const fs = require("fs");
const os = require("os");
const path = require("path");
const Module = require("module");

const distRoot = path.join(__dirname, "..", "dist");

class EventEmitter {
    constructor() {
        this.listeners = new Set();
        this.event = (listener) => {
            this.listeners.add(listener);
            return { dispose: () => this.listeners.delete(listener) };
        };
    }
    fire(value) {
        for (const listener of [...this.listeners]) {
            listener(value);
        }
    }
    dispose() {
        this.listeners.clear();
    }
}

class McpStdioServerDefinition {
    constructor(label, command, args = [], env = {}, version) {
        this.label = label;
        this.command = command;
        this.args = args;
        this.env = env;
        this.version = version;
    }
}

class LanguageModelTextPart {
    constructor(value) {
        this.value = value;
    }
}

class LanguageModelToolResult {
    constructor(content) {
        this.content = content;
    }
}

class RelativePattern {
    constructor(base, pattern) {
        this.base = base;
        this.pattern = pattern;
    }
}

function createVscodeMock(options = {}) {
    const state = {
        workspaceFolders: options.workspaceFolders ?? [],
        workspaceFile: undefined,
        configuration: { "aprodaAldc.alMcp.start": "auto", ...(options.configuration ?? {}) },
        alExtension: options.alExtension,
        messages: [],
        choices: [],
        executedCommands: [],
        commandFailure: undefined,
        registeredCommands: new Map(),
        registeredTools: new Map(),
        registeredProviders: new Map(),
        watchers: [],
        terminals: [],
        quickPicks: [],
        events: {
            workspaceFolders: new EventEmitter(),
            configuration: new EventEmitter(),
            extensions: new EventEmitter(),
            debugSession: new EventEmitter()
        }
    };

    const showMessage = (level) => (message, ...items) => {
        state.messages.push({ level, message, items });
        const choice = state.choices.length > 0 ? state.choices.shift() : undefined;
        return Promise.resolve(typeof choice === "function" ? choice(items) : choice);
    };

    const vscode = {
        EventEmitter,
        McpStdioServerDefinition,
        LanguageModelTextPart,
        LanguageModelToolResult,
        RelativePattern,
        Disposable: class { constructor(callOnDispose) { this.dispose = callOnDispose; } },
        Uri: {
            file: (fsPath) => ({ fsPath, scheme: "file", toString: () => `file://${fsPath}` }),
            joinPath: (base, ...segments) => ({ fsPath: path.join(base.fsPath, ...segments), scheme: "file" })
        },
        workspace: {
            get workspaceFolders() { return state.workspaceFolders; },
            get workspaceFile() { return state.workspaceFile; },
            getConfiguration: (section) => ({
                get: (key, defaultValue) => {
                    const value = state.configuration[`${section}.${key}`];
                    return value === undefined ? defaultValue : value;
                }
            }),
            onDidChangeWorkspaceFolders: (listener) => state.events.workspaceFolders.event(listener),
            onDidChangeConfiguration: (listener) => state.events.configuration.event(listener),
            createFileSystemWatcher: (pattern) => {
                const emitters = { change: new EventEmitter(), create: new EventEmitter(), delete: new EventEmitter() };
                const watcher = {
                    pattern,
                    disposed: false,
                    onDidChange: emitters.change.event,
                    onDidCreate: emitters.create.event,
                    onDidDelete: emitters.delete.event,
                    emit: (kind = "change") => emitters[kind].fire(),
                    dispose: () => { watcher.disposed = true; }
                };
                state.watchers.push(watcher);
                return watcher;
            }
        },
        window: {
            showWarningMessage: showMessage("warning"),
            showInformationMessage: showMessage("info"),
            showErrorMessage: showMessage("error"),
            createTerminal: (terminalOptions) => {
                const terminal = { options: terminalOptions, shown: false, show() { terminal.shown = true; } };
                state.terminals.push(terminal);
                return terminal;
            },
            createQuickPick: () => {
                const accept = new EventEmitter();
                const hide = new EventEmitter();
                const quickPick = {
                    items: [],
                    selectedItems: [],
                    hidden: false,
                    onDidAccept: accept.event,
                    onDidHide: hide.event,
                    show: () => { },
                    hide: () => { quickPick.hidden = true; hide.fire(); },
                    dispose: () => { },
                    accept: (item) => { quickPick.selectedItems = item ? [item] : []; accept.fire(); },
                    close: () => hide.fire()
                };
                state.quickPicks.push(quickPick);
                return quickPick;
            }
        },
        commands: {
            registerCommand: (name, handler) => {
                state.registeredCommands.set(name, handler);
                return { dispose: () => state.registeredCommands.delete(name) };
            },
            executeCommand: async (name, ...args) => {
                state.executedCommands.push({ name, args });
                if (state.commandFailure) {
                    throw state.commandFailure;
                }
                return undefined;
            }
        },
        lm: {
            registerTool: (name, tool) => {
                state.registeredTools.set(name, tool);
                return { dispose: () => state.registeredTools.delete(name) };
            },
            registerMcpServerDefinitionProvider: (id, provider) => {
                state.registeredProviders.set(id, provider);
                return { dispose: () => state.registeredProviders.delete(id) };
            }
        },
        extensions: {
            getExtension: (id) => (id === "ms-dynamics-smb.al" ? state.alExtension : undefined),
            onDidChange: (listener) => state.events.extensions.event(listener)
        },
        debug: {
            onDidStartDebugSession: (listener) => state.events.debugSession.event(listener)
        }
    };
    return { vscode, state };
}

async function withVscode(mock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? mock.vscode : originalLoad.call(this, request, parent, isMain);
    };
    for (const key of Object.keys(require.cache)) {
        if (key.startsWith(distRoot)) {
            delete require.cache[key];
        }
    }
    try {
        return await fn((relative) => require(path.join(distRoot, relative)));
    } finally {
        Module._load = originalLoad;
    }
}

function write(filePath, content) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, content);
}

const defaultLaunch = {
    version: "0.2.0",
    configurations: [
        { name: "attach-only", type: "al", request: "attach" },
        { name: "dev-win", type: "al", request: "launch", server: "http://dev.example.com", serverInstance: "BC", authentication: "Windows" },
        { name: "dev-up", type: "al", request: "launch", server: "https://up.example.com", serverInstance: "BC", authentication: "UserPassword", port: 7050 }
    ]
};

// Builds <scratch>/<name> as a git repository with an AL project "Base", aldc.yaml, and (by default) the starter.
function makeRepo(scratch, name, options = {}) {
    const root = path.join(scratch, name);
    fs.mkdirSync(path.join(root, ".git"), { recursive: true });
    const toolkit = options.toolkit ?? "github";
    const toolkitRoot = toolkit === "github" ? ".github" : ".";
    const configurationPath = toolkit === "github" ? path.join(root, ".github", "aldc.yaml") : path.join(root, "aldc.yaml");
    write(configurationPath, options.aldcYaml ?? `toolkitRoot: "${toolkitRoot}"\naproda:\n  layerVersion: "1.2.0_aproda.test"\n`);
    write(path.join(root, "Base", "app.json"), "{}");
    if (options.launch !== null) {
        write(path.join(root, "Base", ".vscode", "launch.json"), typeof options.launch === "string" ? options.launch : JSON.stringify(options.launch ?? defaultLaunch, null, 2));
    }
    if (options.starter !== false) {
        write(path.join(root, toolkitRoot, "skills", "skill-aproda-al-mcp", "scripts", "Start-AprodaAlMcp.ps1"), "# starter");
        write(path.join(root, toolkitRoot, "skills", "skill-aproda-fkh", "scripts", "FkhCredentialStore.ps1"), "# store");
    }
    if (options.local !== undefined) {
        const localPath = toolkit === "github" ? path.join(root, ".github", "aldc.local.json") : path.join(root, "aldc.local.json");
        write(localPath, typeof options.local === "string" ? options.local : JSON.stringify(options.local, null, 2));
    }
    return root;
}

function makeScratch(prefix) {
    return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function localJson(launchProject, launchConfig) {
    return { version: 1, target: { launchProject, launchConfig } };
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function waitFor(condition, description, timeoutMs = 2000) {
    const deadline = Date.now() + timeoutMs;
    while (!condition()) {
        if (Date.now() > deadline) {
            throw new Error(`Timed out waiting for ${description}`);
        }
        await sleep(5);
    }
}

const noCancellation = { isCancellationRequested: false, onCancellationRequested: () => ({ dispose() { } }) };

function createLogger() {
    const lines = [];
    return { lines, info: (message) => lines.push(message), error: (message) => lines.push(`ERROR: ${message}`), show() { }, dispose() { } };
}

// Workspace folder of the AL project (app.json at its root) inside a makeRepo() repository.
function projectFolder(repo, project = "Base") {
    return { uri: { fsPath: path.join(repo, project) }, name: project };
}

async function runTests(tests) {
    const scratch = makeScratch("al-mcp-test-");
    let failed = 0;
    try {
        for (const [name, test] of Object.entries(tests)) {
            try {
                await test(scratch);
                console.log(`ok - ${name}`);
            } catch (error) {
                failed++;
                console.error(`not ok - ${name}\n${error && error.stack ? error.stack : error}`);
            }
        }
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
    if (failed > 0) {
        console.error(`${failed} of ${Object.keys(tests).length} test(s) failed.`);
        process.exit(1);
    }
    console.log(`${Object.keys(tests).length} test(s) passed.`);
}

module.exports = { createVscodeMock, withVscode, makeRepo, makeScratch, localJson, defaultLaunch, write, runTests, distRoot, sleep, waitFor, noCancellation, createLogger, projectFolder };
