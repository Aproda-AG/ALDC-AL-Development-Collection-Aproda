const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const globalUpdates = [];
const existingWindowsEnv = { OTHER_VAR: "keep" };
const vscodeMock = {
    workspace: {
        textDocuments: [],
        workspaceFolders: [],
        getConfiguration: (section) => {
            if (section === "terminal.integrated.env") {
                return {
                    get: (platform) => (platform === "windows" ? existingWindowsEnv : undefined),
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
        // and must still push BCQUALITY_HOME to the Global setting for windows/linux/osx.
        await reconcileBcquality(repositoryRoot, bcqualityRoot, logger);

        const source = await fs.readFile(workspacePath, "utf8");
        assert.strictEqual(source, originalWorkspaceSource, "the tracked workspace file must be left untouched");

        assert.strictEqual(globalUpdates.length, 3, "BCQUALITY_HOME must be written for windows, linux and osx");
        for (const platform of ["windows", "linux", "osx"]) {
            const update = globalUpdates.find((entry) => entry.platform === platform);
            assert.ok(update, `expected an update for ${platform}`);
            assert.strictEqual(update.target, vscodeMock.ConfigurationTarget.Global);
            assert.strictEqual(update.value.BCQUALITY_HOME, bcqualityRoot);
        }
        const windowsUpdate = globalUpdates.find((entry) => entry.platform === "windows");
        assert.strictEqual(windowsUpdate.value.OTHER_VAR, "keep", "existing env entries must be merged, not replaced");
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
