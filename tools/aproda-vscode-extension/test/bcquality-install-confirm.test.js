const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

// Regression guard: a fresh clone at a convention-derived path must never happen silently.
// An existing clone the resolver temporarily lost track of looks exactly like a first-time install,
// and cloning anyway leaves a duplicate behind plus a global setting pointing at it.

function makeHarness({ devRoot = "", bcqualityPath = "", answer = undefined, workspaceFolders = [] }) {
    const prompts = [];
    const updates = [];
    const gitCalls = [];
    const vscodeMock = {
        workspace: {
            workspaceFolders,
            getConfiguration: () => ({
                get: (key, defaultValue) => {
                    if (key === "devRoot") { return devRoot; }
                    if (key === "bcquality.path") { return bcqualityPath; }
                    return defaultValue;
                },
                inspect: () => undefined,
                update: async (key, value) => { updates.push({ key, value }); }
            })
        },
        window: {
            showWarningMessage: async (message, options) => {
                prompts.push({ message, detail: options && options.detail });
                return answer;
            },
            showInformationMessage: async () => undefined,
            showErrorMessage: async () => undefined,
            withProgress: async (_options, task) => task({ report: () => undefined }),
            createOutputChannel: () => ({ appendLine: () => undefined, show: () => undefined, dispose: () => undefined })
        },
        ProgressLocation: { Notification: 15 },
        ConfigurationTarget: { Global: 1 },
        env: { openExternal: async () => undefined },
        Uri: { file: (value) => ({ fsPath: value }) }
    };
    const processMock = {
        run: async (_command, args) => {
            gitCalls.push(args);
            return { code: 0, stdout: "", stderr: "" };
        }
    };
    return { vscodeMock, processMock, prompts, updates, gitCalls };
}

async function withInstaller(harness, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        if (request === "vscode") { return harness.vscodeMock; }
        if (request === "../process" && parent && parent.filename.includes("install")) { return harness.processMock; }
        return originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of ["../dist/bcquality/install", "../dist/bcquality/resolve", "../dist/bcquality/aldcConfig", "../dist/env/gitRoot", "../dist/env/devRoot", "../dist/config"]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        return await fn(require("../dist/bcquality/install"));
    } finally {
        Module._load = originalLoad;
    }
}

const logger = { info: () => undefined, error: () => undefined, warn: () => undefined, show: () => undefined };

async function run() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-install-confirm-"));
    try {
        // Cancelling the prompt must leave nothing behind.
        const cancelRoot = path.join(scratch, "cancel");
        await fs.mkdir(cancelRoot, { recursive: true });
        const cancel = makeHarness({ devRoot: cancelRoot, answer: undefined });
        const cancelResult = await withInstaller(cancel, ({ installOrUpdateBcquality }) => installOrUpdateBcquality(logger));
        assert.strictEqual(cancelResult, undefined, "cancelled install must not report a ready clone");
        assert.strictEqual(cancel.prompts.length, 1, "a missing clone must be confirmed before cloning");
        assert.strictEqual(cancel.gitCalls.length, 0, "cancelling must not run git");
        assert.strictEqual(cancel.updates.length, 0, "cancelling must not write the global path setting");

        // Confirming clones to the announced target.
        const acceptRoot = path.join(scratch, "accept");
        await fs.mkdir(acceptRoot, { recursive: true });
        const accept = makeHarness({ devRoot: acceptRoot, answer: "Clone" });
        const target = path.join(acceptRoot, "BCQuality-Aproda");
        const acceptResult = await withInstaller(accept, ({ installOrUpdateBcquality }) => installOrUpdateBcquality(logger));
        assert.strictEqual(acceptResult, target);
        assert.strictEqual(accept.prompts.length, 1);
        assert.ok(accept.prompts[0].detail.includes(target), "the prompt must name the target path");
        assert.deepStrictEqual(accept.gitCalls[0][0], "clone");
        assert.deepStrictEqual(accept.gitCalls[0][2], target);

        // An existing clone is updated without asking.
        const existingRoot = path.join(scratch, "existing");
        const existingTarget = path.join(existingRoot, "BCQuality-Aproda");
        await fs.mkdir(path.join(existingTarget, ".git"), { recursive: true });
        const existing = makeHarness({ devRoot: existingRoot, answer: undefined });
        const existingResult = await withInstaller(existing, ({ installOrUpdateBcquality }) => installOrUpdateBcquality(logger));
        assert.strictEqual(existingResult, existingTarget);
        assert.strictEqual(existing.prompts.length, 0, "updating an existing clone must not prompt");
        assert.deepStrictEqual(existing.gitCalls[0][0], "pull");
        assert.deepStrictEqual(existing.updates, [{ key: "bcquality.path", value: existingTarget }]);

        // A configured path that does not resolve must survive: it is a deliberate user choice, and
        // silently replacing it hides the misconfiguration behind a success message.
        const mounted = path.join(scratch, "mounted-clone");
        await fs.mkdir(path.join(mounted, "skills"), { recursive: true });
        await fs.writeFile(path.join(mounted, "skills", "entry.md"), "# entry");
        await fs.mkdir(path.join(mounted, ".git"), { recursive: true });
        const configuredElsewhere = path.join(scratch, "user-chose-this");
        const keep = makeHarness({
            bcqualityPath: configuredElsewhere,
            workspaceFolders: [{ uri: { fsPath: mounted } }],
            answer: undefined
        });
        const keepResult = await withInstaller(keep, ({ installOrUpdateBcquality }) => installOrUpdateBcquality(logger));
        assert.strictEqual(keepResult, mounted, "the verified rung wins when the configured path does not resolve");
        assert.strictEqual(keep.prompts.length, 1, "the user must be told the configured path was not used");
        assert.deepStrictEqual(keep.updates, [], "a differing configured path must never be silently overwritten");
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
    console.log("BCQuality install confirmation tests passed.");
}

run().catch((error) => {
    console.error(error);
    process.exit(1);
});
