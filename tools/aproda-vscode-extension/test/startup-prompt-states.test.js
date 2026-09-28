const assert = require("assert");
const Module = require("module");

const vscodeMock = {};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { startupPrompt } = require("../dist/startup/check");
Module._load = originalLoad;

// The defect this covers: a project on a moving channel that has never been applied yields `unknown`,
// and `unknown` used to produce no startup notification at all -- indistinguishable from "up to date",
// so a pilot machine would silently stay behind. Measured live on "Gustav Gerig AG Base", 2026-09-28.
function testUnknownSpeaksUp() {
    const prompt = startupPrompt({ status: "unknown", available: "ded1ccd8", message: "no applied commit yet" }, undefined);
    assert.ok(prompt, "an unknown state must produce a startup prompt");
    assert.strictEqual(prompt.kind, "apply");
    assert.strictEqual(prompt.message, "no applied commit yet");
    // The action must lead to applying the toolkit; "Later"/"Never" must remain available.
    assert.deepStrictEqual([...prompt.actions], ["Apply Toolkit", "Later", "Never for this project"]);
}

function testNotInstalledAndOutdatedUnchanged() {
    const install = startupPrompt({ status: "notInstalled", message: "not installed" }, undefined);
    assert.strictEqual(install.kind, "install");
    assert.deepStrictEqual([...install.actions], ["Install", "Later", "Never for this project"]);

    const update = startupPrompt({ status: "outdated", available: "ded1ccd8", message: "update available" }, undefined);
    assert.strictEqual(update.kind, "update");
    assert.deepStrictEqual([...update.actions], ["Update", "Preview Changes", "Later", "Skip this version"]);
}

// A popup before every window for a transient network failure would be noise, and `ahead`/`current`
// are informational. Only states the user can act on may interrupt.
function testSilentStates() {
    for (const status of ["current", "ahead", "invalid", "unavailable"]) {
        assert.strictEqual(
            startupPrompt({ status, available: "x", message: status }, undefined),
            undefined,
            `${status} must stay silent at startup`
        );
    }
}

function testSkipStillSuppressesThatVersion() {
    const outdated = { status: "outdated", available: "ded1ccd8", message: "update available" };
    assert.strictEqual(startupPrompt(outdated, "ded1ccd8"), undefined, "a skipped version must not prompt again");
    assert.ok(startupPrompt(outdated, "0000000"), "a different skipped version must not suppress this one");

    // The skip list is version-scoped; it must not leak into the "apply once" state, which carries no
    // installed version to skip.
    const unknown = { status: "unknown", available: "ded1ccd8", message: "no applied commit yet" };
    assert.ok(startupPrompt(unknown, "ded1ccd8"), "skipping a version must not silence the unknown state");
}

testUnknownSpeaksUp();
testNotInstalledAndOutdatedUnchanged();
testSilentStates();
testSkipStillSuppressesThatVersion();
console.log("Startup prompt state tests passed.");
