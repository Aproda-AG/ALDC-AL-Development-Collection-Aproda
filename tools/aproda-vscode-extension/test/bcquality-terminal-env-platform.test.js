const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const globalUpdates = [];
const existingGlobalEnv = {
    windows: undefined,
    linux: { OTHER_VAR: "keep-linux", BCQUALITY_HOME: "stale-linux" },
    osx: { OTHER_VAR: "keep-osx", BCQUALITY_HOME: "stale-osx" }
};
const vscodeMock = {
    workspace: {
        workspaceFolders: [],
        getConfiguration: (section) => {
            if (section === "terminal.integrated.env") {
                return {
                    get: (_key, defaultValue) => defaultValue,
                    inspect: (platform) => ({ globalValue: existingGlobalEnv[platform] }),
                    update: (platform, value, target) => {
                        globalUpdates.push({ platform, value, target });
                        return Promise.resolve();
                    }
                };
            }
            return { get: (_key, defaultValue) => defaultValue, inspect: () => undefined };
        }
    },
    ConfigurationTarget: { Global: 1 }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { reconcileBcquality } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

// FIX 1 / FIX 2, simulated on win32 regardless of the host actually running the test.
async function testPruneKeepsOtherVars() {
    const originalPlatform = process.platform;
    Object.defineProperty(process, "platform", { value: "win32" });

    const previousBcqualityHome = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    const repositoryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-win32-env-"));
    const bcqualityRoot = path.join(path.dirname(repositoryRoot), "BCQuality-Aproda");
    try {
        const logger = { info: () => undefined, error: () => undefined };
        await reconcileBcquality(repositoryRoot, bcqualityRoot, logger);

        assert.strictEqual(globalUpdates.length, 3, "one update per platform key: the write plus two prunes");

        const windowsUpdate = globalUpdates.find((entry) => entry.platform === "windows");
        assert.ok(windowsUpdate, "only terminal.integrated.env.windows may receive BCQUALITY_HOME on win32");
        assert.strictEqual(windowsUpdate.value.BCQUALITY_HOME, bcqualityRoot);

        for (const platform of ["linux", "osx"]) {
            const update = globalUpdates.find((entry) => entry.platform === platform);
            assert.ok(update, `expected a pruning update for ${platform}`);
            assert.ok(
                !update.value || !("BCQUALITY_HOME" in update.value),
                `a pre-existing BCQUALITY_HOME under ${platform} must be removed on win32`
            );
            assert.strictEqual(update.value.OTHER_VAR, `keep-${platform}`, `other developer variables under ${platform} must survive`);
        }
    } finally {
        Object.defineProperty(process, "platform", { value: originalPlatform });
        if (previousBcqualityHome === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousBcqualityHome;
        }
        await fs.rm(repositoryRoot, { recursive: true, force: true });
    }
}

// FIX 3: an inactive platform whose only Global value is BCQUALITY_HOME must be pruned to `undefined`,
// not left as `{}` -- this branch was previously untested because both fixtures above pair it with OTHER_VAR.
async function testPruneToEmptyRemovesOverride() {
    const originalPlatform = process.platform;
    Object.defineProperty(process, "platform", { value: "win32" });

    existingGlobalEnv.windows = undefined;
    existingGlobalEnv.linux = { BCQUALITY_HOME: "stale" };
    existingGlobalEnv.osx = { OTHER_VAR: "keep-osx", BCQUALITY_HOME: "stale-osx" };
    globalUpdates.length = 0;

    const previousBcqualityHome = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    const repositoryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-win32-env-"));
    const bcqualityRoot = path.join(path.dirname(repositoryRoot), "BCQuality-Aproda");
    try {
        const logger = { info: () => undefined, error: () => undefined };
        await reconcileBcquality(repositoryRoot, bcqualityRoot, logger);

        const linuxUpdate = globalUpdates.find((entry) => entry.platform === "linux");
        assert.ok(linuxUpdate, "expected a pruning update for linux");
        assert.strictEqual(linuxUpdate.value, undefined, "pruning the only key must remove the override entirely, not leave {}");

        const osxUpdate = globalUpdates.find((entry) => entry.platform === "osx");
        assert.ok(osxUpdate, "expected a pruning update for osx");
        assert.strictEqual(osxUpdate.value.OTHER_VAR, "keep-osx", "other developer variables under osx must survive");
        assert.ok(!("BCQUALITY_HOME" in osxUpdate.value), "BCQUALITY_HOME must be removed under osx");
    } finally {
        Object.defineProperty(process, "platform", { value: originalPlatform });
        if (previousBcqualityHome === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousBcqualityHome;
        }
        await fs.rm(repositoryRoot, { recursive: true, force: true });
    }
}

async function main() {
    await testPruneKeepsOtherVars();
    await testPruneToEmptyRemovesOverride();
}

main().then(() => console.log("BCQuality win32 terminal-env platform tests passed."));
