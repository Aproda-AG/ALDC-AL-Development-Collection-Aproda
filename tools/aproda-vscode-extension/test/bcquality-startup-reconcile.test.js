const assert = require("assert");
const fsp = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

// Measured on HEKS Base (2026-09-28): an init that adds the `.external` root to the *.code-workspace
// makes VS Code reload the window, the extension host dies, and the junction step after the bootstrap
// never runs. These cover the startup reconciliation that makes the state converge anyway -- and the
// three ways that reconciliation could damage a healthy setup.

const settingsWrites = [];
const globalEnv = { windows: {} };
const vscodeMock = {
    workspace: {
        getConfiguration: () => ({
            get: (_key, fallback) => fallback,
            inspect: (platform) => ({ globalValue: globalEnv[platform] }),
            update: async (platform, value) => { settingsWrites.push({ platform, value }); globalEnv[platform] = value; }
        })
    },
    ConfigurationTarget: { Global: 1 }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { shouldReconcileOnStartup, createBcqualityLink, removeBcqualityLink, updateBcqualityHomeGlobalSetting } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

function recordingLogger() {
    const lines = [];
    return { lines, info: (m) => lines.push(m), error: (m) => lines.push(`ERROR: ${m}`) };
}

function testStartupGate() {
    // Disabled must still run, so a stray link gets removed even though nothing resolved.
    assert.strictEqual(shouldReconcileOnStartup({ enabled: false, verified: false, root: undefined }), true);
    // Nothing resolved and not disabled: staying silent avoids writing an empty BCQUALITY_HOME.
    assert.strictEqual(shouldReconcileOnStartup({ enabled: "auto", verified: false, root: undefined }), false);
    // "verified" without a root would still yield an empty path.
    assert.strictEqual(shouldReconcileOnStartup({ enabled: "auto", verified: true, root: undefined }), false);
    assert.strictEqual(shouldReconcileOnStartup({ enabled: "auto", verified: true, root: "C:\\clone" }), true);
}

async function withTempDir(run) {
    const base = await fsp.mkdtemp(path.join(os.tmpdir(), "aldc-startup-"));
    try {
        return await run(base);
    } finally {
        await fsp.rm(base, { recursive: true, force: true });
    }
}

// Running on every activation must not churn the filesystem: a correct link is left exactly as it is,
// and in particular is never removed and recreated (which would briefly break every open editor on it).
async function testHealthyLinkIsUntouched() {
    await withTempDir(async (base) => {
        const target = path.join(base, "clone");
        const linkPath = path.join(base, ".external", "bcquality");
        await fsp.mkdir(target, { recursive: true });
        await fsp.mkdir(path.dirname(linkPath), { recursive: true });
        await fsp.symlink(target, linkPath, process.platform === "win32" ? "junction" : "dir");
        const before = (await fsp.lstat(linkPath)).birthtimeMs;

        const logger = recordingLogger();
        await createBcqualityLink(linkPath, target, logger);

        assert.ok(logger.lines.some((l) => l.startsWith("BCQuality link already correct")), "the already-correct branch must be taken");
        assert.ok(!logger.lines.some((l) => l.startsWith("ERROR")), `no error may be logged, got: ${logger.lines.join(" | ")}`);
        assert.ok(!logger.lines.some((l) => l.startsWith("Removed BCQuality link")), "a healthy link must never be removed");
        assert.strictEqual((await fsp.lstat(linkPath)).birthtimeMs, before, "the link must not be recreated");
        assert.strictEqual(await fsp.realpath(linkPath), await fsp.realpath(target), "the link must still reach its target");
    });
}

// The one operation that could destroy real work: removal must refuse anything that is not a link,
// however often it now runs.
async function testRemoveRefusesRealDirectory() {
    await withTempDir(async (base) => {
        const notALink = path.join(base, ".external", "bcquality");
        await fsp.mkdir(notALink, { recursive: true });
        await fsp.writeFile(path.join(notALink, "precious.md"), "do not delete");

        const logger = recordingLogger();
        await removeBcqualityLink(notALink, logger);

        assert.ok(logger.lines.some((l) => l.includes("not a link")), "removal must refuse a real directory");
        assert.strictEqual(await fsp.readFile(path.join(notALink, "precious.md"), "utf8"), "do not delete");
    });
}

// Without this guard the Global settings file would be rewritten in every window, and two projects
// resolving to different clones would flap it against each other (the B-28 damage pattern).
async function testEnvIsWrittenOnlyWhenItDiffers() {
    const target = "C:\\clone";

    globalEnv.windows = { BCQUALITY_HOME: target };
    settingsWrites.length = 0;
    await updateBcqualityHomeGlobalSetting(target);
    assert.strictEqual(settingsWrites.length, 0, `an unchanged BCQUALITY_HOME must not be written, got ${JSON.stringify(settingsWrites)}`);

    globalEnv.windows = { BCQUALITY_HOME: "C:\\old", KEEP_ME: "1" };
    settingsWrites.length = 0;
    await updateBcqualityHomeGlobalSetting(target);
    assert.strictEqual(settingsWrites.length, 1, "a changed value must be written exactly once");
    assert.strictEqual(settingsWrites[0].value.BCQUALITY_HOME, target);
    assert.strictEqual(settingsWrites[0].value.KEEP_ME, "1", "unrelated variables must survive the update");
}

async function main() {
    testStartupGate();
    await testHealthyLinkIsUntouched();
    await testRemoveRefusesRealDirectory();
    await testEnvIsWrittenOnlyWhenItDiffers();
}

main().then(() => console.log("BCQuality startup reconciliation tests passed."));
