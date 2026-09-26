const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

// Regression guard: the bootstrap unmounts the pre-migration BCQuality root. Resolving only afterwards
// makes an existing clone look like a first-time install, which is how a duplicate clone gets created.
// The resolution must therefore be captured before the bootstrap runs.

const logger = { info: () => undefined, error: () => undefined, warn: () => undefined, show: () => undefined };

async function run() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-init-bcq-"));
    try {
        const repoRoot = path.join(scratch, "project");
        await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
        const clone = path.join(scratch, "BCQuality-Aproda");
        await fs.mkdir(path.join(clone, "skills"), { recursive: true });
        await fs.writeFile(path.join(clone, "skills", "entry.md"), "# entry");

        const reconciled = [];
        const folders = [{ uri: { fsPath: repoRoot } }, { uri: { fsPath: clone } }];
        const vscodeMock = {
            workspace: {
                workspaceFolders: folders,
                getConfiguration: () => ({
                    get: (_key, defaultValue) => defaultValue,
                    inspect: () => undefined,
                    update: async () => undefined
                })
            },
            window: {
                showInformationMessage: async () => undefined,
                showWarningMessage: async () => undefined,
                showErrorMessage: async () => undefined,
                withProgress: async (_options, task) => task({ report: () => undefined }),
                createOutputChannel: () => ({ appendLine: () => undefined, show: () => undefined, dispose: () => undefined })
            },
            ProgressLocation: { Notification: 15 },
            ConfigurationTarget: { Global: 1 },
            commands: { executeCommand: async () => undefined },
            Uri: { file: (value) => ({ fsPath: value }) }
        };
        const bridgeMock = {
            runBootstrap: async () => {
                // What the real migration does: the sibling BCQuality root stops being a workspace folder.
                vscodeMock.workspace.workspaceFolders = [{ uri: { fsPath: repoRoot } }];
                return { changes: 1 };
            }
        };

        const originalLoad = Module._load;
        Module._load = function (request, parent, isMain) {
            if (request === "vscode") { return vscodeMock; }
            if (request === "../ps/bridge") { return bridgeMock; }
            if (request === "../process") { return { run: async () => ({ code: 0, stdout: "", stderr: "" }) }; }
            if (request === "../workspace/bcqualityRoot") {
                return { reconcileBcquality: async (_repo, root) => { reconciled.push(root); } };
            }
            return originalLoad.call(this, request, parent, isMain);
        };
        for (const mod of ["../dist/commands/initProject", "../dist/bcquality/install", "../dist/bcquality/resolve", "../dist/bcquality/aldcConfig", "../dist/env/gitRoot", "../dist/env/devRoot", "../dist/config"]) {
            delete require.cache[require.resolve(mod)];
        }
        try {
            const { initializeProject } = require("../dist/commands/initProject");
            const source = { ensure: async () => ({ path: path.join(scratch, "fork"), mode: "localFork" }) };
            await initializeProject(source, logger, false, repoRoot);

            assert.deepStrictEqual(reconciled, [clone], "the clone known before the bootstrap must be the one reconciled");

            // Makes the guard falsifiable: post-bootstrap the clone is genuinely unresolvable,
            // so passing can only come from the pre-bootstrap capture.
            const { resolveBcquality } = require("../dist/bcquality/resolve");
            const after = await resolveBcquality();
            assert.strictEqual(after.verified, false, "the clone must be unresolvable after the bootstrap");
        } finally {
            Module._load = originalLoad;
        }

        await firstInitUsesPostBootstrapConfig(scratch);
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
    console.log("Init project BCQuality pre-resolution tests passed.");
}

// The mirror case: nothing is resolvable before the bootstrap, because the bootstrap is what writes
// aldc.yaml. The fallback must therefore probe the post-bootstrap state, not a pre-bootstrap snapshot.
async function firstInitUsesPostBootstrapConfig(scratch) {
    const repoRoot = path.join(scratch, "fresh-project");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    const declaredHome = path.join(repoRoot, ".external", "bcquality");

    const reconciled = [];
    const vscodeMock = {
        workspace: {
            workspaceFolders: [{ uri: { fsPath: repoRoot } }],
            getConfiguration: () => ({
                get: (_key, defaultValue) => defaultValue,
                inspect: () => undefined,
                update: async () => undefined
            })
        },
        window: {
            showInformationMessage: async () => undefined,
            showWarningMessage: async () => undefined,
            showErrorMessage: async () => undefined,
            withProgress: async (_options, task) => task({ report: () => undefined }),
            createOutputChannel: () => ({ appendLine: () => undefined, show: () => undefined, dispose: () => undefined })
        },
        ProgressLocation: { Notification: 15 },
        ConfigurationTarget: { Global: 1 },
        commands: { executeCommand: async () => undefined },
        Uri: { file: (value) => ({ fsPath: value }) }
    };
    const bridgeMock = {
        runBootstrap: async () => {
            await fs.mkdir(path.join(repoRoot, ".github"), { recursive: true });
            await fs.writeFile(path.join(repoRoot, ".github", "aldc.yaml"), "external:\n  bcquality:\n    home: .external/bcquality\n");
            await fs.mkdir(path.join(declaredHome, "skills"), { recursive: true });
            await fs.writeFile(path.join(declaredHome, "skills", "entry.md"), "# entry");
            return { changes: 1 };
        }
    };

    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        if (request === "vscode") { return vscodeMock; }
        if (request === "../ps/bridge") { return bridgeMock; }
        if (request === "../process") { return { run: async () => ({ code: 0, stdout: "", stderr: "" }) }; }
        if (request === "../workspace/bcqualityRoot") {
            return { reconcileBcquality: async (_repo, root) => { reconciled.push(root); } };
        }
        return originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of ["../dist/commands/initProject", "../dist/bcquality/install", "../dist/bcquality/resolve", "../dist/bcquality/aldcConfig", "../dist/env/gitRoot", "../dist/env/devRoot", "../dist/config"]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        const { initializeProject } = require("../dist/commands/initProject");
        const source = { ensure: async () => ({ path: path.join(scratch, "fork"), mode: "localFork" }) };
        await initializeProject(source, logger, false, repoRoot);
        assert.deepStrictEqual(reconciled, [declaredHome], "the home declared by the bootstrap-written aldc.yaml must be reconciled");
    } finally {
        Module._load = originalLoad;
    }
}

run().catch((error) => {
    console.error(error);
    process.exit(1);
});
