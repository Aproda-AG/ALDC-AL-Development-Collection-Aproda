// S-3.18: manual-mode first start waits until VS Code fetched the definition before issuing startServer.
const assert = require("assert");
const {
    createVscodeMock, withVscode, makeRepo, localJson, runTests, sleep, noCancellation, createLogger, projectFolder
} = require("./al-mcp-helpers");

let counter = 0;
const nextName = () => `race-${++counter}`;
const toolName = "aprodaAldc_startAlMcp";
const providerId = "aprodaAldc.alMcp";

async function withRegistration(setup, fn) {
    const mock = createVscodeMock(setup);
    const logger = createLogger();
    const context = { subscriptions: [], extension: { id: "AprodaAG.Aproda-ALDC" } };
    return withVscode(mock, async (load) => {
        const { registerAlMcp } = load("alMcp/register");
        const { startDelays } = load("alMcp/control");
        registerAlMcp(context, logger);
        const provider = mock.state.registeredProviders.get(providerId);
        const saved = { ...startDelays };
        try {
            await sleep(40);
            return await fn({ state: mock.state, provider, logger, startDelays });
        } finally {
            Object.assign(startDelays, saved);
            for (const subscription of context.subscriptions) {
                subscription.dispose();
            }
        }
    });
}

const manual = (repo) => ({ workspaceFolders: [projectFolder(repo)], configuration: { "aprodaAldc.alMcp.start": "manual" } });
const startCalls = (state) => state.executedCommands.filter((call) => call.name === "workbench.mcp.startServer");
const invoke = async (state) => JSON.parse((await state.registeredTools.get(toolName).invoke({ input: { action: "start" } }, noCancellation)).content[0].value);

const tests = {
    async "S-3.18 manual first start: startServer only after the definition was fetched"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration(manual(repo), async ({ state, provider, startDelays }) => {
            startDelays.fetchTimeoutMs = 2000;
            startDelays.settleMs = 20;
            await provider.provideMcpServerDefinitions();
            let fetched = false;
            provider.onDidChangeMcpServerDefinitions(() => {
                setTimeout(async () => {
                    assert.strictEqual(startCalls(state).length, 0, "no start before the fetch");
                    fetched = true;
                    await provider.provideMcpServerDefinitions();
                }, 60);
            });
            const result = await invoke(state);
            assert.strictEqual(result.state, "started");
            assert.ok(fetched, "the fetch happened before the call returned");
            assert.strictEqual(startCalls(state).length, 1);
        });
    },

    async "S-3.18 manual first start: timeout still issues the command and warns"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration(manual(repo), async ({ state, logger, startDelays }) => {
            startDelays.fetchTimeoutMs = 50;
            startDelays.settleMs = 20;
            const result = await invoke(state);
            assert.strictEqual(result.state, "started");
            assert.strictEqual(startCalls(state).length, 1);
            assert.ok(logger.lines.some((line) => line.startsWith("WARNING: AL MCP definition was not fetched")), "warning logged");
        });
    },

    async "S-3.18 auto mode and an already requested start do not wait"(scratch) {
        const repo = makeRepo(scratch, nextName(), { local: localJson("Base", "dev-win") });
        await withRegistration({ workspaceFolders: [projectFolder(repo)] }, async ({ state, logger, startDelays }) => {
            startDelays.fetchTimeoutMs = 5000;
            const begin = Date.now();
            await invoke(state);
            assert.ok(Date.now() - begin < 1000, "auto: no wait");
            assert.ok(!logger.lines.some((line) => line.includes("not fetched")));
        });
        await withRegistration(manual(repo), async ({ state, provider, logger, startDelays }) => {
            startDelays.fetchTimeoutMs = 5000;
            provider.requestStart();
            const begin = Date.now();
            await invoke(state);
            assert.ok(Date.now() - begin < 1000, "already requested: no wait");
            assert.ok(!logger.lines.some((line) => line.includes("not fetched")));
        });
    }
};

runTests(tests);
