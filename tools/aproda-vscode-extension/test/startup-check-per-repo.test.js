const assert = require("assert");
const Module = require("module");

const vscodeMock = {};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { shouldRunStartupCheck, markStartupCheckComplete, resetUpdateCheckState } = require("../dist/startup/check");
Module._load = originalLoad;

function makeContext() {
    const store = new Map();
    return {
        globalState: {
            get: (key, defaultValue) => (store.has(key) ? store.get(key) : defaultValue),
            update: async (key, value) => {
                if (value === undefined) {
                    store.delete(key);
                } else {
                    store.set(key, value);
                }
            },
            keys: () => Array.from(store.keys())
        },
        workspaceState: {
            update: async () => undefined
        }
    };
}

async function main() {
    const context = makeContext();
    const repoA = "C:\\repos\\project-a";
    const repoB = "C:\\repos\\project-b";

    // Both due before either has run.
    assert.strictEqual(shouldRunStartupCheck(context, repoA, 24), true);
    assert.strictEqual(shouldRunStartupCheck(context, repoB, 24), true);

    await markStartupCheckComplete(context, repoA);

    // Project A's check must not suppress project B's own interval (per-repository key, D-50 §3.5).
    assert.strictEqual(shouldRunStartupCheck(context, repoA, 24), false);
    assert.strictEqual(shouldRunStartupCheck(context, repoB, 24), true);

    await markStartupCheckComplete(context, repoB);
    assert.strictEqual(shouldRunStartupCheck(context, repoB, 24), false);

    await resetUpdateCheckState(context);
    assert.strictEqual(shouldRunStartupCheck(context, repoA, 24), true);
    assert.strictEqual(shouldRunStartupCheck(context, repoB, 24), true);
}

main().then(() => console.log("Startup check per-repository interval tests passed."));
