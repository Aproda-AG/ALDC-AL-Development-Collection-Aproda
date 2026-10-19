// S-3.9 (startAlMcp tool), S-3.13 (start mode), S-3.7 (Select AL Target), S-3.11 (doctor), S-3.12 (debug hint),
// plus the registered commands. The whole wiring runs through registerAlMcp with a mocked vscode.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
    createVscodeMock, withVscode, makeRepo, localJson, write, runTests, sleep, waitFor, noCancellation, createLogger, projectFolder
} = require("./al-mcp-helpers");

let counter = 0;
const nextName = () => `repo-${++counter}`;
const toolName = "aprodaAldc_startAlMcp";
const providerId = "aprodaAldc.alMcp";

// registerAlMcp against a mocked vscode; `fn` gets the mock state, the registered provider and a way to settle async work.
async function withRegistration(setup, fn) {
    const mock = createVscodeMock(setup);
    const logger = createLogger();
    const context = { subscriptions: [] };
    return withVscode(mock, async (load) => {
        const { registerAlMcp } = load("alMcp/register");
        const serverCommands = load("alMcp/serverCommands");
        registerAlMcp(context, logger);
        const provider = mock.state.registeredProviders.get(providerId);
        try {
            await sleep(40);
            return await fn({ state: mock.state, provider, logger, load, serverCommands, context });
        } finally {
            for (const subscription of context.subscriptions) {
                subscription.dispose();
            }
        }
    });
}

const startCalls = (state) => state.executedCommands.filter((call) => call.name === "workbench.mcp.startServer");
const configurationEvent = { affectsConfiguration: (key) => key === "aprodaAldc.alMcp.start" };

async function invokeTool(state, input) {
    const tool = state.registeredTools.get(toolName);
    const result = await tool.invoke({ input }, noCancellation);
    return JSON.parse(result.content[0].value);
}

const tests = {
    async "registration: provider, tool and the four commands are registered"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state }) => {
            assert.ok(state.registeredProviders.has(providerId));
            assert.ok(state.registeredTools.has(toolName));
            for (const command of ["aprodaAldc.selectAlTarget", "aprodaAldc.startAlMcp", "aprodaAldc.restartAlMcp", "aprodaAldc.storeAlCredential"]) {
                assert.ok(state.registeredCommands.has(command), command);
            }
            const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "package.json"), "utf8"));
            for (const command of manifest.contributes.commands.map((entry) => entry.command).filter((name) => /AlTarget|AlMcp|AlCredential/.test(name))) {
                assert.ok(state.registeredCommands.has(command), `contributed command ${command} is registered`);
            }
        });
    },

    async "S-3.9 tool: start in auto issues the start command with the own id"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state, serverCommands }) => {
            state.executedCommands.length = 0;
            const result = await invokeTool(state, { action: "start" });
            assert.strictEqual(result.state, "started");
            assert.strictEqual(result.server, "al-mcp");
            assert.deepStrictEqual(state.executedCommands, [{ name: "workbench.mcp.startServer", args: [serverCommands.ownServerIdCandidate] }]);
        });
    },

    async "S-3.9 tool: start in manual sets the start flag, fires onDidChange, then starts"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.alMcp.start": "manual" } }, async ({ state, provider }) => {
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
            assert.strictEqual(startCalls(state).length, 0, "manual: no automatic start");
            const order = [];
            provider.onDidChangeMcpServerDefinitions(() => order.push("onDidChange"));
            const originalExecute = state.executedCommands.push.bind(state.executedCommands);
            state.executedCommands.push = (call) => { order.push(call.name); return originalExecute(call); };
            const result = await invokeTool(state, { action: "start" });
            assert.strictEqual(result.state, "started");
            assert.deepStrictEqual(order, ["onDidChange", "workbench.mcp.startServer"], "flag + event first, then the command");
            assert.strictEqual((await provider.provideMcpServerDefinitions()).length, 1, "definition provided after the request");
        });
    },

    async "S-3.9 tool: restart, manual restart without request, no AL workspace, failures, ignored extras"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state, serverCommands, logger }) => {
            state.executedCommands.length = 0;
            const restarted = await invokeTool(state, { action: "restart" });
            assert.strictEqual(restarted.state, "restarted");
            assert.deepStrictEqual(state.executedCommands, [{ name: "workbench.mcp.restartServer", args: [serverCommands.ownServerIdCandidate] }]);

            state.executedCommands.length = 0;
            await invokeTool(state, { action: "start", serverId: "evil/other-server", server: "x", args: ["y"] });
            assert.deepStrictEqual(state.executedCommands, [{ name: "workbench.mcp.startServer", args: [serverCommands.ownServerIdCandidate] }], "model input never reaches the command");

            state.executedCommands.length = 0;
            const invalid = await invokeTool(state, { action: "stop" });
            assert.strictEqual(invalid.state, "failed");
            assert.deepStrictEqual(state.executedCommands, []);

            state.commandFailure = new Error("command not found");
            const failed = await invokeTool(state, { action: "start" });
            assert.strictEqual(failed.state, "failed");
            assert.ok(logger.lines.some((line) => line.includes("workbench.mcp.startServer failed") && line.includes("Q-23")), "failure logged with Q-23 reference");
            state.commandFailure = undefined;

            const prepared = await state.registeredTools.get(toolName).prepareInvocation({ input: { action: "start" } });
            assert.ok(prepared.confirmationMessages, "the user confirms every call");
            assert.ok(prepared.confirmationMessages.message.includes(repo), prepared.confirmationMessages.message);
        });

        await withRegistration({ workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.alMcp.start": "manual" } }, async ({ state }) => {
            const result = await invokeTool(state, { action: "restart" });
            assert.strictEqual(result.state, "started", "a manual restart of a never-provided server becomes a start");
            assert.strictEqual(startCalls(state).length, 1);
            assert.strictEqual(state.executedCommands.filter((call) => call.name === "workbench.mcp.restartServer").length, 0);
        });

        await withRegistration({ workspaceFolders: [{ uri: { fsPath: repo }, name: "repo" }] }, async ({ state }) => {
            const result = await invokeTool(state, { action: "start" });
            assert.strictEqual(result.state, "notAlWorkspace");
            assert.deepStrictEqual(state.executedCommands, []);
        });
    },

    async "S-3.13 start mode: activation per mode and workspace"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state }) => {
            assert.strictEqual(startCalls(state).length, 1, "auto + AL workspace: one start call");
        });
        await withRegistration({ workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.alMcp.start": "manual" } }, async ({ state, provider }) => {
            assert.strictEqual(startCalls(state).length, 0, "manual: no start call");
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
        });
        await withRegistration({ workspaceFolders: [{ uri: { fsPath: repo }, name: "repo" }] }, async ({ state, provider }) => {
            assert.strictEqual(startCalls(state).length, 0, "no app.json: no start call");
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
        });
    },

    async "S-3.13 start mode: an AL folder added later starts once"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [{ uri: { fsPath: repo }, name: "repo" }] }, async ({ state }) => {
            assert.strictEqual(startCalls(state).length, 0);
            state.workspaceFolders = [projectFolder(repo)];
            state.events.workspaceFolders.fire({});
            await waitFor(() => startCalls(state).length === 1, "the start after the folder change");
            state.events.workspaceFolders.fire({});
            await sleep(60);
            assert.strictEqual(startCalls(state).length, 1, "not started a second time");
        });
    },

    async "S-3.13 start mode: auto -> manual -> auto at runtime"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state, provider }) => {
            assert.strictEqual(startCalls(state).length, 1);
            assert.strictEqual((await provider.provideMcpServerDefinitions()).length, 1);

            state.configuration["aprodaAldc.alMcp.start"] = "manual";
            state.events.configuration.fire(configurationEvent);
            await sleep(60);
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), [], "definition removed in manual mode");
            assert.strictEqual(startCalls(state).length, 1, "no start in manual mode");

            state.configuration["aprodaAldc.alMcp.start"] = "auto";
            state.events.configuration.fire(configurationEvent);
            await waitFor(() => startCalls(state).length === 2, "the start after switching back to auto");
            assert.strictEqual((await provider.provideMcpServerDefinitions()).length, 1, "definition provided again");
            await sleep(60);
            assert.strictEqual(startCalls(state).length, 2, "exactly one more start");
        });
    },

    async "S-3.13 start mode: no start call when no definition exists (no toolkit)"(scratch) {
        const repo = makeRepo(scratch, nextName(), { starter: false });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state }) => {
            assert.strictEqual(startCalls(state).length, 0, "nothing to start without the starter script");
        });
    },

    async "S-3.7 Select AL Target: items, blocked item not selectable, atomic strict-JSON write"(scratch) {
        const launch = {
            configurations: [
                { name: "attach-only", type: "al", request: "attach" },
                { name: "dev-win", server: "http://dev.example.com", serverInstance: "BC", authentication: "Windows" },
                { name: "dev-up", server: "https://up.example.com", serverInstance: "BC", authentication: "UserPassword" },
                { name: "no-auth", server: "http://na.example.com", serverInstance: "BC" }
            ]
        };
        const repo = makeRepo(scratch, nextName(), { launch });
        const mock = createVscodeMock({ workspaceFolders: [projectFolder(repo)] });
        const logger = createLogger();
        await withVscode(mock, async (load) => {
            const { selectAlTarget } = load("alMcp/selectTarget");
            const pending = selectAlTarget(logger);
            await waitFor(() => mock.state.quickPicks.length === 1, "the picker");
            const picker = mock.state.quickPicks[0];
            assert.deepStrictEqual(picker.items.map((item) => item.label), ["dev-win", "dev-up", "no-auth"], "only server configurations");
            const byLabel = (label) => picker.items.find((item) => item.label === label);
            assert.strictEqual(byLabel("dev-up").description, "https://up.example.com/BC");
            assert.strictEqual(byLabel("dev-up").detail, "UserPassword · Base");
            assert.strictEqual(byLabel("no-auth").detail, "authentication missing · Base · blocked: AUTH_MISSING");

            picker.accept(byLabel("no-auth"));
            assert.strictEqual(picker.hidden, false, "a blocked item does not close the picker");
            assert.ok(picker.placeholder.includes("AUTH_MISSING"));
            assert.ok(!fs.existsSync(path.join(repo, ".github", "aldc.local.json")), "nothing written");

            picker.accept(byLabel("dev-up"));
            assert.strictEqual(await pending, true);
            const filePath = path.join(repo, ".github", "aldc.local.json");
            assert.strictEqual(fs.readFileSync(filePath, "utf8"), '{\n  "version": 1,\n  "target": {\n    "launchProject": "Base",\n    "launchConfig": "dev-up"\n  }\n}\n');
            assert.ok(!fs.existsSync(`${filePath}.tmp`));
            assert.strictEqual(mock.state.messages.at(-1).message, "Target selected. Deploying still needs the environment confirmation in chat.");

            const cancelled = selectAlTarget(logger);
            await waitFor(() => mock.state.quickPicks.length === 2, "the second picker");
            mock.state.quickPicks[1].close();
            assert.strictEqual(await cancelled, false);
        });
    },

    async "commands: store credential for a Windows target needs nothing; start/restart commands report"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state }) => {
            await state.registeredCommands.get("aprodaAldc.storeAlCredential")();
            assert.strictEqual(state.terminals.length, 0, "no terminal for Windows authentication");
            assert.ok(state.messages.at(-1).message.includes("no stored credential is needed"));

            state.messages.length = 0;
            await state.registeredCommands.get("aprodaAldc.startAlMcp")();
            assert.strictEqual(state.messages[0].level, "info");
            await state.registeredCommands.get("aprodaAldc.restartAlMcp")();
            assert.ok(state.executedCommands.some((call) => call.name === "workbench.mcp.restartServer"));
        });
        const upRepo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-up") });
        await withRegistration({ workspaceFolders: [projectFolder(upRepo)] }, async ({ state }) => {
            await state.registeredCommands.get("aprodaAldc.storeAlCredential")();
            assert.strictEqual(state.terminals.length, 1, "terminal for UserPassword");
            assert.ok(state.terminals[0].options.shellArgs.at(-1).includes("Save-FkhCredential -Key 'up.example.com'"));
        });
    },

    async "S-3.11 doctor: duplicate registration, altool, start mode, autostart hint"(scratch) {
        const dirty = makeRepo(scratch, nextName(), {});
        write(path.join(dirty, "Base", ".vscode", "mcp.json"), '{ "servers": { "al": { "command": "altool.exe", "args": ["launchmcpserver", "."] } } }');
        const clean = makeRepo(scratch, nextName(), {});
        write(path.join(clean, "Base", ".vscode", "mcp.json"), '{ "servers": { "other": { "command": "x" } } }');
        const workspaceFile = path.join(scratch, "w.code-workspace");
        write(workspaceFile, '{ "settings": { "mcp": { "servers": { "al": { "args": ["LaunchMcpServer"] } } } } }');
        const extensionRoot = path.join(scratch, "ext", "ms-dynamics-smb.al-18.1.0");
        write(path.join(extensionRoot, "bin", "win32", "altool.exe"), "");

        const find = async (setup) => {
            const mock = createVscodeMock(setup);
            mock.state.workspaceFile = setup.workspaceFile;
            return withVscode(mock, async (load) => load("alMcp/doctorChecks").collectAlMcpFindings());
        };

        const findings = await find({ workspaceFolders: [projectFolder(dirty), projectFolder(clean)], alExtension: { extensionPath: extensionRoot, packageJSON: { version: "18.1.0" } } });
        const duplicates = findings.filter((finding) => finding.message.startsWith("Duplicate AL MCP registration"));
        assert.strictEqual(duplicates.length, 1, "only the folder whose mcp.json contains launchmcpserver");
        assert.strictEqual(duplicates[0].level, "warning");
        assert.ok(duplicates[0].message.includes(path.join(dirty, "Base", ".vscode", "mcp.json")));
        assert.ok(findings.some((finding) => finding.message === "AL MCP start mode: auto"));
        assert.ok(findings.some((finding) => finding.message.includes("altool (active AL extension 18.1.0)") && finding.message.includes(path.join("bin", "win32", "altool.exe"))));

        const viaWorkspaceFile = await find({ workspaceFolders: [projectFolder(clean)], workspaceFile: { scheme: "file", fsPath: workspaceFile } });
        assert.strictEqual(viaWorkspaceFile.filter((finding) => finding.message.startsWith("Duplicate AL MCP registration")).length, 1, "workspace file is checked too");
        assert.ok(viaWorkspaceFile.some((finding) => finding.message.includes("not installed")), "AL extension missing is reported");

        const none = await find({ workspaceFolders: [projectFolder(clean)] });
        assert.strictEqual(none.filter((finding) => finding.level === "warning").length, 0);

        const autostartNever = await find({ workspaceFolders: [projectFolder(clean)], configuration: { "chat.mcp.autostart": "never" } });
        assert.ok(autostartNever.some((finding) => finding.level === "warning" && finding.message.includes("chat.mcp.autostart")));
        const manualNever = await find({ workspaceFolders: [projectFolder(clean)], configuration: { "chat.mcp.autostart": "never", "aprodaAldc.alMcp.start": "manual" } });
        assert.ok(!manualNever.some((finding) => finding.message.includes("chat.mcp.autostart")), "manual mode is not affected");
    },

    async "S-3.12 debug hint: one notification per other configuration name, never silent"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        const mock = createVscodeMock({ workspaceFolders: [projectFolder(repo)] });
        const logger = createLogger();
        const context = { subscriptions: [] };
        await withVscode(mock, async (load) => {
            load("alMcp/debugHint").registerDebugHint(context, logger);
            const session = (name, type = "al") => ({ type, configuration: { name }, workspaceFolder: projectFolder(repo) });
            const fire = (value) => mock.state.events.debugSession.fire(value);
            const localPath = path.join(repo, ".github", "aldc.local.json");
            const original = fs.readFileSync(localPath, "utf8");

            mock.state.choices.push("Keep");
            fire(session("dev-up"));
            await waitFor(() => mock.state.messages.length === 1, "the switch notification");
            assert.strictEqual(mock.state.messages[0].message, "Switch ALDC target to dev-up?");
            assert.deepStrictEqual(mock.state.messages[0].items, ["Switch", "Keep"]);

            fire(session("dev-win"));
            fire(session("dev-up"));
            fire(session("dev-up", "node"));
            await sleep(80);
            assert.strictEqual(mock.state.messages.length, 1, "same name as target, repeated name and non-AL sessions: none");
            assert.strictEqual(fs.readFileSync(localPath, "utf8"), original, "Keep never changes the file");

            mock.state.choices.push("Switch");
            fire(session("no-auth"));
            await waitFor(() => mock.state.messages.length >= 2, "second notification for another name");
            await sleep(40);
            assert.strictEqual(fs.readFileSync(localPath, "utf8"), original, "'no-auth' does not exist: target unchanged");

            fs.writeFileSync(path.join(repo, "Base", ".vscode", "launch.json"), JSON.stringify({
                configurations: [
                    { name: "dev-win", server: "http://dev.example.com", serverInstance: "BC", authentication: "Windows" },
                    { name: "dev-up", server: "https://up.example.com", serverInstance: "BC", authentication: "UserPassword" },
                    { name: "other", server: "http://o.example.com", serverInstance: "BC", authentication: "Windows" }
                ]
            }));
            mock.state.choices.push("Switch");
            fire(session("other"));
            await waitFor(() => JSON.parse(fs.readFileSync(localPath, "utf8")).target.launchConfig === "other", "the confirmed switch");
        });
    }
};

runTests(tests);
