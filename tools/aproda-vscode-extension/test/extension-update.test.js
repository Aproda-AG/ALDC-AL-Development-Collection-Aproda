const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const https = require("https");
const { EventEmitter } = require("events");
const Module = require("module");

function fakeHttpsResponse(body, statusCode = 200, headers = {}) {
    const response = new EventEmitter();
    response.statusCode = statusCode;
    response.headers = headers;
    response.resume = () => undefined;
    process.nextTick(() => {
        response.emit("data", Buffer.from(body));
        response.emit("end");
    });
    return response;
}

// Regression test for the "No Servers" bug: workbench.extensions.installExtension
// rejects any Uri whose scheme isn't file/vscode-remote.
async function testInstallUsesFileSchemeUri() {
    const executedCommands = [];
    const vscodeMock = {
        authentication: { getSession: async () => ({ accessToken: "token" }) },
        commands: { executeCommand: async (command, ...args) => { executedCommands.push({ command, args }); } },
        Uri: { file: (fsPath) => ({ scheme: "file", fsPath }) }
    };

    const originalHttpsGet = https.get;
    https.get = (url, _options, callback) => {
        const isGitHubApi = new URL(url).hostname === "api.github.com";
        callback(isGitHubApi
            ? fakeHttpsResponse(JSON.stringify({ assets: [{ name: "aproda-aldc-0.1.6.vsix", url: "https://example.invalid/asset" }] }))
            : fakeHttpsResponse("vsix-bytes"));
        return { on: () => undefined };
    };

    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    const { installExtensionUpdate } = require("../dist/extensionUpdate/service");
    Module._load = originalLoad;

    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-install-"));
    try {
        const context = { globalStorageUri: { fsPath: tempRoot } };
        const logger = { info: () => undefined, error: () => undefined };
        await installExtensionUpdate(context, { current: "0.1.5", available: "0.1.6", tag: "vscode-ext/v0.1.6" }, logger);

        assert.strictEqual(executedCommands.length, 1);
        assert.strictEqual(executedCommands[0].command, "workbench.extensions.installExtension");
        const targetUri = executedCommands[0].args[0];
        assert.strictEqual(targetUri.scheme, "file", "installExtensionUpdate must target a file-scheme Uri, or VS Code rejects it with 'No Servers'.");
        assert.strictEqual(await fs.readFile(targetUri.fsPath, "utf8"), "vsix-bytes");
    } finally {
        https.get = originalHttpsGet;
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

// Regression test for "Invalid combination of options": createIfNone and forceNewSession
// are mutually exclusive on vscode.authentication.getSession.
async function testRetryUsesSingleAuthOption() {
    const getSessionCalls = [];
    let errorMessageCallCount = 0;
    const vscodeMock = {
        window: {
            showInformationMessage: async () => undefined,
            showErrorMessage: async () => {
                errorMessageCallCount += 1;
                return errorMessageCallCount === 1 ? "Sign In / Retry" : undefined;
            },
            withProgress: async (_options, task) => task()
        },
        authentication: {
            getSession: async (_providerId, _scopes, options) => {
                getSessionCalls.push(options);
                return { accessToken: "token" };
            }
        },
        ProgressLocation: { Notification: 1 }
    };
    const serviceMock = {
        findExtensionUpdate: async () => { throw new Error("boom"); },
        installExtensionUpdate: async () => undefined
    };

    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        if (request === "vscode") {
            return vscodeMock;
        }
        if (request === "../extensionUpdate/service") {
            return serviceMock;
        }
        return originalLoad.call(this, request, parent, isMain);
    };
    const { checkForExtensionUpdates } = require("../dist/commands/extensionUpdate");
    Module._load = originalLoad;

    const context = { globalState: { get: () => undefined, update: async () => undefined } };
    const logger = { info: () => undefined, error: () => undefined, show: () => undefined };
    await checkForExtensionUpdates(context, logger, false);

    assert.strictEqual(getSessionCalls.length, 1);
    assert.deepStrictEqual(getSessionCalls[0], { forceNewSession: true }, "Sign In / Retry must not combine createIfNone with forceNewSession.");
}

async function main() {
    await testInstallUsesFileSchemeUri();
    await testRetryUsesSingleAuthOption();
}

main().then(() => console.log("Extension update tests passed."));
