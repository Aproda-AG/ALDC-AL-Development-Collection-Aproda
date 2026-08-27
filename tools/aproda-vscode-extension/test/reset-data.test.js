const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const configurationUpdates = [];
const vscodeMock = {
    ConfigurationTarget: { Global: "global" },
    workspace: {
        getConfiguration: () => ({
            get: (_key, defaultValue) => defaultValue,
            update: async (key, value, target) => configurationUpdates.push({ key, value, target })
        })
    },
    window: {}
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};

const { globalSettingKeys, resetGlobalSettings } = require("../dist/config");
const { resetUpdateCheckState } = require("../dist/startup/check");
const { LayerSource } = require("../dist/source/layerSource");
Module._load = originalLoad;

async function main() {
    await resetGlobalSettings();
    assert.deepStrictEqual(configurationUpdates, globalSettingKeys.map((key) => ({ key, value: undefined, target: "global" })));

    const updates = [];
    const context = {
        globalState: { update: async (key, value) => updates.push({ scope: "global", key, value }) },
        workspaceState: { update: async (key, value) => updates.push({ scope: "workspace", key, value }) }
    };
    await resetUpdateCheckState(context);
    assert.deepStrictEqual(updates, [
        { scope: "global", key: "lastLayerUpdateCheck", value: undefined },
        { scope: "workspace", key: "skippedLayerVersion", value: undefined },
        { scope: "workspace", key: "layerUpdateChecksDisabled", value: undefined }
    ]);

    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-reset-"));
    try {
        const cacheFile = path.join(tempRoot, "layer-cache", "fork", "cache.txt");
        const localForkFile = path.join(tempRoot, "local-fork", "keep.txt");
        await fs.mkdir(path.dirname(cacheFile), { recursive: true });
        await fs.mkdir(path.dirname(localForkFile), { recursive: true });
        await fs.writeFile(cacheFile, "cache");
        await fs.writeFile(localForkFile, "local fork");
        const logger = { info: () => undefined, error: () => undefined, show: () => undefined };
        await new LayerSource({ globalStorageUri: { fsPath: tempRoot } }, logger).clearCache();
        await assert.rejects(fs.access(cacheFile));
        assert.strictEqual(await fs.readFile(localForkFile, "utf8"), "local fork");
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("Reset data tests passed."));