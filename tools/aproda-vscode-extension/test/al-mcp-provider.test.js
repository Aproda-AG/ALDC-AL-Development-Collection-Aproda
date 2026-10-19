// S-3.2, S-3.3, S-3.5, S-3.6, S-3.8, S-3.10, S-3.14: the MCP server definition provider.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
    createVscodeMock, withVscode, makeRepo, localJson, write, runTests, sleep, waitFor, noCancellation, createLogger, projectFolder
} = require("./al-mcp-helpers");

const alExtension = (version = "18.1.0") => ({ extensionPath: `C:\\ext\\ms-dynamics-smb.al-${version}`, packageJSON: { version } });

let counter = 0;
const nextName = () => `repo-${++counter}`;

async function withLocalAppData(scratch, fn) {
    const previous = process.env.LOCALAPPDATA;
    const localAppData = path.join(scratch, `localappdata-${++counter}`);
    fs.mkdirSync(localAppData, { recursive: true });
    process.env.LOCALAPPDATA = localAppData;
    try {
        return await fn(localAppData);
    } finally {
        if (previous === undefined) {
            delete process.env.LOCALAPPDATA;
        } else {
            process.env.LOCALAPPDATA = previous;
        }
    }
}

// Provider with a mocked vscode; debounce/notification waits are shortened so the tests stay fast.
async function withProvider(setup, fn) {
    const mock = createVscodeMock(setup.mock);
    const logger = createLogger();
    return withVscode(mock, async (load) => {
        const { AlMcpProvider } = load("alMcp/provider");
        const provider = new AlMcpProvider(logger, { debounceMs: 30, notificationWaitMs: 150, ...(setup.options ?? {}) });
        try {
            return await fn({ provider, mock, state: mock.state, logger, load });
        } finally {
            provider.dispose();
        }
    });
}

const tests = {
    async "S-3.2 provider returns [] outside an AL workspace"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withProvider({ mock: { workspaceFolders: [{ uri: { fsPath: repo }, name: "repo" }] } }, async ({ provider }) => {
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
        });
    },

    async "S-3.2 provider returns [] in manual mode until a start was requested"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.alMcp.start": "manual" } } }, async ({ provider }) => {
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
            let fired = 0;
            provider.onDidChangeMcpServerDefinitions(() => fired++);
            provider.requestStart();
            assert.strictEqual(fired, 1, "requestStart fires onDidChange");
            assert.strictEqual((await provider.provideMcpServerDefinitions()).length, 1);
        });
    },

    async "S-3.2 provider returns [] when the repository does not resolve"(scratch) {
        const repo = makeRepo(scratch, nextName(), {});
        fs.rmSync(path.join(repo, ".github", "aldc.yaml"));
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider }) => {
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
        });
    },

    async "S-3.2 provider returns [] and logs once when the starter is missing"(scratch) {
        const repo = makeRepo(scratch, nextName(), { starter: false, local: localJson("Base", "dev-win") });
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider, logger }) => {
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
            assert.deepStrictEqual(await provider.provideMcpServerDefinitions(), []);
            const lines = logger.lines.filter((line) => line.includes("starter script not found"));
            assert.strictEqual(lines.length, 1, "logged exactly once");
            assert.ok(lines[0].includes("Start-AprodaAlMcp.ps1"));
        });
    },

    async "S-3.2 normal definition: label, command, env, cwd, args"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withProvider({
            mock: { workspaceFolders: [projectFolder(repo)], alExtension: alExtension(), configuration: { "aprodaAldc.pwshPath": "pwsh-custom" } }
        }, async ({ provider }) => {
            const definitions = await provider.provideMcpServerDefinitions();
            assert.strictEqual(definitions.length, 1);
            const [definition] = definitions;
            assert.strictEqual(definition.label, "al-mcp");
            assert.strictEqual(definition.command, "pwsh-custom");
            assert.deepStrictEqual(definition.env, {}, "no target or credential values");
            assert.strictEqual(definition.cwd.fsPath, repo);
            assert.match(definition.version, /^[0-9a-f]{12}$/);
            assert.deepStrictEqual(definition.args.slice(0, 3), ["-NoProfile", "-NonInteractive", "-Command"]);
            assert.strictEqual(definition.args.length, 4, "one -Command argument");
            const starter = path.join(repo, ".github", "skills", "skill-aproda-al-mcp", "scripts", "Start-AprodaAlMcp.ps1");
            const skill = path.join(repo, ".github", "skills", "skill-aproda-al-mcp");
            assert.strictEqual(definition.args[3], `& ([ScriptBlock]::Create((Get-Content -LiteralPath '${starter}' -Raw))) -RepositoryRoot '${repo}' -SkillRoot '${skill}' -AlExtensionPath 'C:\\ext\\ms-dynamics-smb.al-18.1.0' -AlExtensionVersion '18.1.0'`);
        });
    },

    async "S-3.2 -AlExtension* omitted when the AL extension is not installed"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider }) => {
            const [definition] = await provider.provideMcpServerDefinitions();
            assert.ok(!definition.args[3].includes("-AlExtension"));
            assert.strictEqual(definition.command, "pwsh", "default pwsh path");
        });
    },

    async "S-3.3 quoting: repository path with ' and spaces"(scratch) {
        const repo = makeRepo(scratch, "my repo it's here", { local: localJson("Base", "dev-win") });
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider }) => {
            const [definition] = await provider.provideMcpServerDefinitions();
            assert.strictEqual(definition.args.length, 4, "still one -Command argument");
            const quoted = repo.replace(/'/g, "''");
            assert.ok(definition.args[3].includes(`-RepositoryRoot '${quoted}'`), definition.args[3]);
            assert.ok(quoted.includes("it''s"), "single quote doubled");
            assert.ok(definition.args[3].includes(`-LiteralPath '${path.join(repo, ".github", "skills", "skill-aproda-al-mcp", "scripts", "Start-AprodaAlMcp.ps1").replace(/'/g, "''")}'`));
        });
        await withVscode(createVscodeMock(), async (load) => {
            const { psQuote } = load("alMcp/psQuote");
            assert.strictEqual(psQuote("a'b"), "'a''b'");
            assert.strictEqual(psQuote("a\u2019b"), "'a\u2019\u2019b'", "typographic quotes end a PowerShell literal too");
        });
    },

    async "S-3.5 version fingerprint: stable, and changes with each input"(scratch) {
        await withLocalAppData(scratch, async (localAppData) => {
            const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-up") });
            await withProvider({ mock: { workspaceFolders: [projectFolder(repo)], alExtension: alExtension("18.1.0") } }, async ({ provider, state }) => {
                const version = async () => (await provider.provideMcpServerDefinitions())[0].version;
                const baseline = await version();
                assert.strictEqual(await version(), baseline, "unchanged inputs twice");

                const localPath = path.join(repo, ".github", "aldc.local.json");
                const original = fs.readFileSync(localPath, "utf8");
                write(localPath, JSON.stringify(localJson("Base", "dev-win"), null, 2));
                const selectionChanged = await version();
                fs.writeFileSync(localPath, original);
                assert.strictEqual(await version(), baseline, "reverting restores the fingerprint");

                const credentialFile = path.join(localAppData, "AprodaFkh", "credentials", "up.example.com.cred.xml");
                write(credentialFile, "x");
                const credentialChanged = await version();
                fs.rmSync(credentialFile);

                state.alExtension = alExtension("18.2.0");
                const alChanged = await version();
                state.alExtension = alExtension("18.1.0");

                const yamlPath = path.join(repo, ".github", "aldc.yaml");
                const yaml = fs.readFileSync(yamlPath, "utf8");
                fs.writeFileSync(yamlPath, yaml.replace("aproda.test", "aproda.next"));
                const layerChanged = await version();
                fs.writeFileSync(yamlPath, yaml);

                const all = [baseline, selectionChanged, credentialChanged, alChanged, layerChanged];
                assert.strictEqual(new Set(all).size, 5, `five distinct values, got ${all.join(", ")}`);
            });
        });
    },

    async "S-3.6 credential file name equals ConvertTo-FkhCredentialStoreFileName"(scratch) {
        // Expected values were produced by dot-sourcing skill-aproda-fkh/scripts/FkhCredentialStore.ps1 in pwsh 7.
        const table = [
            ["dev.example.com", "dev.example.com.cred.xml"],
            ["host:7049", "host_7049.cred.xml"],
            ["a/b\\c", "a_b_c.cred.xml"],
            ["x\x01y\x1fz", "x_y_z.cred.xml"],
            ["q?*|<>\"w", "q______w.cred.xml"],
            ["plain-host_1", "plain-host_1.cred.xml"],
            ["t\tu", "t_u.cred.xml"],
            ["sp ace", "sp ace.cred.xml"],
            ["d\x7fe", "d\x7fe.cred.xml"]
        ];
        await withLocalAppData(scratch, async (localAppData) => {
            await withVscode(createVscodeMock(), async (load) => {
                const credential = load("alMcp/credential");
                for (const [key, expected] of table) {
                    assert.strictEqual(credential.credentialFileName(key), expected, JSON.stringify(key));
                }
                assert.strictEqual(credential.hasStoredCredential("host.example.com"), false);
                write(path.join(localAppData, "AprodaFkh", "credentials", "host.example.com.cred.xml"), "never read");
                assert.strictEqual(credential.hasStoredCredential("host.example.com"), true, "presence by file existence");
                assert.strictEqual(credential.hasStoredCredential(null), false);
                assert.strictEqual(credential.credentialStoreDirectory(""), undefined, "no LOCALAPPDATA, no store");

                const command = credential.buildStoreCredentialCommand("C:\\t k\\it's\\FkhCredentialStore.ps1", "up.example.com");
                assert.ok(command.includes("[ScriptBlock]::Create((Get-Content -LiteralPath 'C:\\t k\\it''s\\FkhCredentialStore.ps1' -Raw))"), "content-based load");
                assert.ok(command.includes("Save-FkhCredential -Key 'up.example.com' -Credential (Get-Credential -Message 'AL target up.example.com')"));
                assert.ok(!/ConvertTo-SecureString|-Password|-AsPlainText/i.test(command), "the extension never handles a password");
            });
        });
    },

    async "S-3.8 resolve: no valid target (absent/stale/invalid) -> notification, definition returned"(scratch) {
        for (const [name, local] of [["absent", undefined], ["stale", localJson("Base", "nope")], ["invalid", "{ not json"]]) {
            const repo = makeRepo(scratch, nextName(), { local });
            await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider, state }) => {
                const [definition] = await provider.provideMcpServerDefinitions();
                state.choices.push("Start build-only");
                const resolved = await provider.resolveMcpServerDefinition(definition, noCancellation);
                assert.strictEqual(resolved, definition, `${name}: definition returned`);
                assert.strictEqual(state.messages.length, 1, `${name}: one notification`);
                assert.strictEqual(state.messages[0].message, "No valid AL target for AL MCP.");
                assert.deepStrictEqual(state.messages[0].items, ["Select target", "Start build-only"]);
            });
        }
    },

    async "S-3.8 resolve: [Select target] runs the picker and the selection is written"(scratch) {
        const repo = makeRepo(scratch, nextName(), {});
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] }, options: { notificationWaitMs: 5000 } }, async ({ provider, state }) => {
            const [definition] = await provider.provideMcpServerDefinitions();
            state.choices.push("Select target");
            const pending = provider.resolveMcpServerDefinition(definition, noCancellation);
            await waitFor(() => state.quickPicks.length === 1, "the target picker");
            const picker = state.quickPicks[0];
            picker.accept(picker.items.find((item) => item.label === "dev-win"));
            assert.strictEqual(await pending, definition);
            const written = JSON.parse(fs.readFileSync(path.join(repo, ".github", "aldc.local.json"), "utf8"));
            assert.deepStrictEqual(written.target, { launchProject: "Base", launchConfig: "dev-win" });
        });
    },

    async "S-3.8 resolve: UserPassword without stored credential -> [Store credential] opens the terminal flow"(scratch) {
        await withLocalAppData(scratch, async () => {
            const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-up") });
            await withProvider({ mock: { workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.pwshPath": "pwsh" } } }, async ({ provider, state }) => {
                const [definition] = await provider.provideMcpServerDefinitions();
                state.choices.push("Store credential");
                assert.strictEqual(await provider.resolveMcpServerDefinition(definition, noCancellation), definition);
                assert.strictEqual(state.messages[0].message, "No stored credential for up.example.com.");
                assert.deepStrictEqual(state.messages[0].items, ["Store credential", "Start build-only"]);
                assert.strictEqual(state.terminals.length, 1, "terminal opened");
                const terminal = state.terminals[0];
                assert.strictEqual(terminal.options.name, "Aproda ALDC: AL credential");
                assert.strictEqual(terminal.options.shellPath, "pwsh");
                const command = terminal.options.shellArgs.at(-1);
                assert.ok(command.includes("Save-FkhCredential -Key 'up.example.com'"));
                assert.ok(command.includes(path.join(repo, ".github", "skills", "skill-aproda-fkh", "scripts", "FkhCredentialStore.ps1")));
            });
        });
    },

    async "S-3.8 resolve: stored credential or Windows authentication -> no notification"(scratch) {
        await withLocalAppData(scratch, async (localAppData) => {
            write(path.join(localAppData, "AprodaFkh", "credentials", "up.example.com.cred.xml"), "x");
            for (const config of ["dev-up", "dev-win"]) {
                const repo = makeRepo(scratch, nextName(), { local: localJson("Base", config) });
                await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider, state }) => {
                    const [definition] = await provider.provideMcpServerDefinitions();
                    assert.strictEqual(await provider.resolveMcpServerDefinition(definition, noCancellation), definition);
                    assert.deepStrictEqual(state.messages, [], config);
                });
            }
        });
    },

    async "S-3.8 resolve: blocking issue -> notification with codes, no buttons, definition returned"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "attach-me"), launch: { configurations: [{ name: "attach-me", server: "http://h.example.com", serverInstance: "BC" }] } });
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider, state }) => {
            const [definition] = await provider.provideMcpServerDefinitions();
            assert.strictEqual(await provider.resolveMcpServerDefinition(definition, noCancellation), definition);
            assert.strictEqual(state.messages.length, 1);
            assert.ok(state.messages[0].message.includes("AUTH_MISSING"));
            assert.deepStrictEqual(state.messages[0].items, []);
        });
    },

    async "S-3.8 resolve: an ignored notification never blocks the start (time limit and cancellation)"(scratch) {
        const repo = makeRepo(scratch, nextName(), {});
        await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] }, options: { notificationWaitMs: 40 } }, async ({ provider, state }) => {
            const [definition] = await provider.provideMcpServerDefinitions();
            state.choices.push(() => new Promise(() => { }));
            const started = Date.now();
            assert.strictEqual(await provider.resolveMcpServerDefinition(definition, noCancellation), definition);
            assert.ok(Date.now() - started < 1500, "returned after the time limit");

            state.choices.push(() => new Promise(() => { }));
            let cancel;
            const token = { isCancellationRequested: false, onCancellationRequested: (listener) => { cancel = listener; return { dispose() { } }; } };
            const pending = provider.resolveMcpServerDefinition(definition, token);
            await waitFor(() => cancel !== undefined, "cancellation subscription");
            cancel();
            assert.strictEqual(await pending, definition);
        });
    },

    async "S-3.10 watchers: one debounced onDidChange per burst"(scratch) {
        await withLocalAppData(scratch, async () => {
            const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
            await withProvider({ mock: { workspaceFolders: [projectFolder(repo)] } }, async ({ provider, state }) => {
                let fired = 0;
                provider.onDidChangeMcpServerDefinitions(() => fired++);
                await provider.provideMcpServerDefinitions();

                const targets = state.watchers.map((watcher) => `${watcher.pattern.base.fsPath}|${watcher.pattern.pattern}`);
                assert.ok(targets.includes(`${path.join(repo, ".github")}|aldc.local.json`), "selection file");
                assert.ok(targets.includes(`${path.join(repo, "Base", ".vscode")}|launch.json`), "selected project's launch.json");
                assert.ok(targets.some((target) => target.endsWith(`${path.sep}credentials|*.cred.xml`)), "credential store folder");

                await provider.provideMcpServerDefinitions();
                assert.strictEqual(state.watchers.length, targets.length, "watchers are not recreated for unchanged targets");

                for (const watcher of state.watchers) {
                    watcher.emit("change");
                    watcher.emit("create");
                    watcher.emit("delete");
                }
                assert.strictEqual(fired, 0, "nothing fires inside the debounce window");
                await sleep(150);
                assert.strictEqual(fired, 1, "one event for the whole burst");

                state.watchers[0].emit("change");
                await sleep(150);
                assert.strictEqual(fired, 2, "a later burst fires again");

                state.events.workspaceFolders.fire();
                state.events.configuration.fire({ affectsConfiguration: (key) => key === "aprodaAldc.alMcp.start" });
                state.events.extensions.fire();
                await sleep(150);
                assert.strictEqual(fired, 3, "workspace folder, setting and extension changes share the debounce");

                state.events.configuration.fire({ affectsConfiguration: () => false });
                await sleep(100);
                assert.strictEqual(fired, 3, "unrelated settings do not fire");

                // A new selection target moves the launch.json watcher.
                write(path.join(repo, ".github", "aldc.local.json"), JSON.stringify(localJson("Base", "dev-up"), null, 2));
                const before = state.watchers.length;
                await provider.provideMcpServerDefinitions();
                assert.strictEqual(state.watchers.length, before, "same project: same watch targets");
            });
        });
    },

    "S-3.14 manifest: setting, provider, commands and tool"() {
        const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "package.json"), "utf8"));
        const setting = manifest.contributes.configuration.properties["aprodaAldc.alMcp.start"];
        assert.deepStrictEqual(setting.enum, ["auto", "manual"]);
        assert.strictEqual(setting.default, "auto");
        assert.strictEqual(setting.scope, "application");
        assert.deepStrictEqual(manifest.contributes.mcpServerDefinitionProviders, [{ id: "aprodaAldc.alMcp", label: "AL MCP (Aproda)" }]);
        const commands = manifest.contributes.commands.map((command) => command.command);
        for (const command of ["aprodaAldc.selectAlTarget", "aprodaAldc.startAlMcp", "aprodaAldc.restartAlMcp", "aprodaAldc.storeAlCredential"]) {
            assert.ok(commands.includes(command), command);
        }
        const tool = manifest.contributes.languageModelTools.find((candidate) => candidate.name === "aprodaAldc_startAlMcp");
        assert.ok(tool);
        assert.strictEqual(tool.toolReferenceName, "startAlMcp");
        assert.strictEqual(tool.when, "aprodaAldc.isAlProject");
        assert.deepStrictEqual(tool.inputSchema.properties.action.enum, ["start", "restart"]);
        assert.deepStrictEqual(tool.inputSchema.required, ["action"]);
        assert.strictEqual(manifest.version, "0.2.0");
    }
};

runTests(tests);
