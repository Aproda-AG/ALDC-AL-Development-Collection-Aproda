const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const globalUpdates = [];
const existingGlobalEnv = {
    windows: { OTHER_VAR: "keep-windows", BCQUALITY_HOME: "stale-windows" },
    linux: { OTHER_VAR: "keep-linux", BCQUALITY_HOME: "stale-linux" },
    osx: { OTHER_VAR: "keep-osx", BCQUALITY_HOME: "stale-osx" }
};
const vscodeMock = {
    workspace: {
        textDocuments: [],
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

// Maps process.platform -> the terminal.integrated.env key expected to receive BCQUALITY_HOME (FIX 1).
const activePlatform = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "osx" : "linux";
const otherPlatforms = ["windows", "linux", "osx"].filter((platform) => platform !== activePlatform);

async function main() {
    const previousBcqualityHome = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    const repositoryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-workspace-"));
    const bcqualityRoot = path.join(path.dirname(repositoryRoot), "BCQuality-Aproda");
    const workspacePath = path.join(repositoryRoot, "project.code-workspace");
    const originalWorkspaceSource = `{
  // Preserve this comment.
  "folders": [{ "name": "BCQuality", "path": "../BCQuality-Aproda" }],
  "settings": {}
}`;
    try {
        await fs.writeFile(workspacePath, originalWorkspaceSource);
        const logger = { info: () => undefined, error: () => undefined };

        // No clone verified anywhere: reconcileBcquality must not touch the tracked *.code-workspace file (D-49),
        // and must only push BCQUALITY_HOME to the platform actually running (FIX 1), reading the Global layer
        // explicitly rather than the effective (workspace+global) one (FIX 2).
        await reconcileBcquality(repositoryRoot, bcqualityRoot, logger);

        const source = await fs.readFile(workspacePath, "utf8");
        assert.strictEqual(source, originalWorkspaceSource, "the tracked workspace file must be left untouched");

        assert.strictEqual(globalUpdates.length, 3, "one update per platform key is expected: one write, two prunes");

        const activeUpdate = globalUpdates.find((entry) => entry.platform === activePlatform);
        assert.ok(activeUpdate, `expected an update for the active platform (${activePlatform})`);
        assert.strictEqual(activeUpdate.target, vscodeMock.ConfigurationTarget.Global);
        assert.strictEqual(activeUpdate.value.BCQUALITY_HOME, bcqualityRoot);
        assert.strictEqual(activeUpdate.value.OTHER_VAR, `keep-${activePlatform}`, "existing entries under the active platform must be merged, not replaced");

        for (const platform of otherPlatforms) {
            const update = globalUpdates.find((entry) => entry.platform === platform);
            assert.ok(update, `expected a pruning update for ${platform}`);
            assert.strictEqual(update.target, vscodeMock.ConfigurationTarget.Global);
            assert.ok(
                !update.value || !("BCQUALITY_HOME" in update.value),
                `BCQUALITY_HOME must not remain under ${platform}`
            );
            assert.strictEqual(update.value.OTHER_VAR, `keep-${platform}`, `other developer variables under ${platform} must survive`);
        }
    } finally {
        if (previousBcqualityHome === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousBcqualityHome;
        }
        await fs.rm(repositoryRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality workspace tests passed."));

