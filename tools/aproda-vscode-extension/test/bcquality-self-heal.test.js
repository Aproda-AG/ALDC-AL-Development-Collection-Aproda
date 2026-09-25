const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

function makeVscodeMock({ bcqualityPath = "", workspaceFolders = [], warnings = [] } = {}) {
    const workspaceStateStore = new Map();
    return {
        workspace: {
            workspaceFolders,
            getConfiguration: (section) => ({
                get: (key, defaultValue) => {
                    if (section === "aprodaAldc" && key === "bcquality.path") {
                        return bcqualityPath;
                    }
                    return defaultValue;
                }
            })
        },
        window: {
            showWarningMessage: async (message) => {
                warnings.push(message);
                return undefined; // user dismisses ("Later"/closed) -- no follow-up command in these tests
            }
        },
        commands: {
            executeCommand: async () => undefined
        },
        // Minimal ExtensionContext stand-in.
        _workspaceState: {
            get: (key) => workspaceStateStore.get(key),
            update: async (key, value) => {
                workspaceStateStore.set(key, value);
            }
        }
    };
}

async function withHealthCheck(vscodeMock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of [
        "../dist/startup/bcqualityHealth",
        "../dist/bcquality/resolve",
        "../dist/bcquality/aldcConfig",
        "../dist/env/gitRoot",
        "../dist/config",
        "../dist/env/devRoot"
    ]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        const { checkBcqualitySelfHeal } = require("../dist/startup/bcqualityHealth");
        return await fn(checkBcqualitySelfHeal);
    } finally {
        Module._load = originalLoad;
    }
}

async function makeVerifiedClone(root) {
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

// FIX 4: verdict "missing" (directory gone) must still notify, distinctly.
async function testMissingCloneNotifies(scratch) {
    const gone = path.join(scratch, "does-not-exist");
    const warnings = [];
    const vscodeMock = makeVscodeMock({ bcqualityPath: gone, warnings });

    await withHealthCheck(vscodeMock, async (checkBcqualitySelfHeal) => {
        await checkBcqualitySelfHeal({ workspaceState: vscodeMock._workspaceState });
    });

    assert.strictEqual(warnings.length, 1, "a missing configured clone must notify exactly once");
    assert.ok(/no longer exists/i.test(warnings[0]), "message must describe the 'gone' case");
}

// FIX 4: verdict "noEntryPoint" (present but not a BCQuality clone) must now also notify, with a distinct message.
async function testBrokenCloneNotifies(scratch) {
    const broken = path.join(scratch, "broken-clone");
    await fs.mkdir(broken, { recursive: true }); // exists, but no skills/entry.md
    const warnings = [];
    const vscodeMock = makeVscodeMock({ bcqualityPath: broken, warnings });

    await withHealthCheck(vscodeMock, async (checkBcqualitySelfHeal) => {
        await checkBcqualitySelfHeal({ workspaceState: vscodeMock._workspaceState });
    });

    assert.strictEqual(warnings.length, 1, "a present-but-broken configured clone must notify exactly once");
    assert.ok(!/no longer exists/i.test(warnings[0]), "message must NOT reuse the 'gone' wording");
    assert.ok(/does not look like a bcquality clone/i.test(warnings[0]), "message must describe the 'broken' case distinctly");
}

// FIX 4 (preserved): the ordinary "nothing configured, nothing installed" state must never nag (§1.6 case 2).
async function testUnconfiguredStaysQuiet(scratch) {
    const warnings = [];
    const vscodeMock = makeVscodeMock({ warnings });

    await withHealthCheck(vscodeMock, async (checkBcqualitySelfHeal) => {
        await checkBcqualitySelfHeal({ workspaceState: vscodeMock._workspaceState });
    });

    assert.strictEqual(warnings.length, 0, "an unconfigured project must never be nagged about BCQuality");
}

// Preserved: a verified, healthy clone must also stay quiet.
async function testVerifiedCloneStaysQuiet(scratch) {
    const clone = path.join(scratch, "clone-healthy");
    await makeVerifiedClone(clone);
    const warnings = [];
    const vscodeMock = makeVscodeMock({ bcqualityPath: clone, warnings });

    await withHealthCheck(vscodeMock, async (checkBcqualitySelfHeal) => {
        await checkBcqualitySelfHeal({ workspaceState: vscodeMock._workspaceState });
    });

    assert.strictEqual(warnings.length, 0, "a verified clone must not trigger a self-heal prompt");
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-self-heal-"));
    const previousEnv = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await testMissingCloneNotifies(scratch);
        await testBrokenCloneNotifies(scratch);
        await testUnconfiguredStaysQuiet(scratch);
        await testVerifiedCloneStaysQuiet(scratch);
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality self-heal tests passed."));
