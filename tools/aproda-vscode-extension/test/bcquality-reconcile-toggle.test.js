const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

function makeVscodeMock({ workspaceFolders = [], autoFixWorkspacePathConfigured = false, autoFixWorkspacePath = true } = {}) {
    return {
        workspace: {
            workspaceFolders,
            getConfiguration: (section) => ({
                get: (key, defaultValue) => {
                    if (section === "aprodaAldc" && key === "bcquality.autoFixWorkspacePath" && autoFixWorkspacePathConfigured) {
                        return autoFixWorkspacePath;
                    }
                    return defaultValue;
                },
                inspect: (key) => {
                    if (section === "aprodaAldc" && key === "bcquality.autoFixWorkspacePath" && autoFixWorkspacePathConfigured) {
                        return { globalValue: autoFixWorkspacePath };
                    }
                    return undefined;
                },
                update: async () => undefined
            })
        },
        ConfigurationTarget: { Global: 1 }
    };
}

async function withReconciler(vscodeMock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of ["../dist/workspace/bcqualityRoot", "../dist/bcquality/resolve", "../dist/bcquality/aldcConfig", "../dist/env/gitRoot", "../dist/config", "../dist/env/devRoot"]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        const { reconcileBcquality, createBcqualityLink } = require("../dist/workspace/bcqualityRoot");
        return await fn(reconcileBcquality, createBcqualityLink);
    } finally {
        Module._load = originalLoad;
    }
}

async function makeVerifiedRoot(root) {
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

// Regression guard for FIX 1: aldc.yaml disabling BCQuality must remove an existing junction
// unconditionally, i.e. even when the (now-additive-only) opt-out setting is explicitly false.
async function runDisabledRemovesJunction(scratch, label, mockOptions) {
    const repoRoot = path.join(scratch, `repo-disabled-${label}`);
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.writeFile(path.join(repoRoot, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");

    const realClone = path.join(scratch, `real-clone-${label}`);
    await makeVerifiedRoot(realClone);

    const linkPath = path.join(repoRoot, ".external", "bcquality");
    const logger = { info: () => undefined, error: () => undefined };

    const previousBcqualityHome = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await withReconciler(
            makeVscodeMock({ workspaceFolders: [{ uri: { fsPath: repoRoot } }], ...mockOptions }),
            async (reconcileBcquality, createBcqualityLink) => {
                await createBcqualityLink(linkPath, realClone, logger);
                const beforeStats = await fs.lstat(linkPath);
                assert.ok(beforeStats.isSymbolicLink(), "fixture setup: junction must exist before reconcile");

                await reconcileBcquality(repoRoot, realClone, logger);

                await assert.rejects(
                    () => fs.lstat(linkPath),
                    `junction must be removed when aldc.yaml disables BCQuality (${label})`
                );
            }
        );

        const remaining = await fs.readdir(path.join(realClone, "skills"));
        assert.deepStrictEqual(remaining, ["entry.md"], "the real clone must survive junction removal");
    } finally {
        if (previousBcqualityHome === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousBcqualityHome;
        }
    }
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-reconcile-toggle-"));
    try {
        await runDisabledRemovesJunction(scratch, "opt-out-default-true", { autoFixWorkspacePathConfigured: false });
        await runDisabledRemovesJunction(scratch, "opt-out-explicit-false", { autoFixWorkspacePathConfigured: true, autoFixWorkspacePath: false });
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality reconcile toggle tests passed."));
