const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const vscodeMock = {
    workspace: {
        textDocuments: [],
        workspaceFolders: [],
        getConfiguration: () => ({ get: (_key, defaultValue) => defaultValue })
    },
    ConfigurationTarget: { Global: 1 }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { createBcqualityLink } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

// B-28 regression: the resolver returning a link's own path as `root` (Fix A regressing, or any future
// caller passing a bad target) must never make it as far as creating a self-referential junction.
async function testRefusesLiteralSelfReference(scratch) {
    const linkPath = path.join(scratch, "self-literal", "bcquality");
    await fs.mkdir(path.dirname(linkPath), { recursive: true });
    const messages = [];
    const logger = { info: () => undefined, error: (message) => messages.push(message) };

    await createBcqualityLink(linkPath, linkPath, logger);

    await assert.rejects(() => fs.lstat(linkPath), "no link must be created when target === linkPath");
    assert.ok(messages.some((message) => message.includes("itself")), "expected a clear log message about the self-reference");
}

// One level removed: `target` is not textually equal to `linkPath`, but realpath(target) resolves to it
// (a link pointing back at the same place). Must be refused, and must not throw.
async function testRefusesRealpathSelfReference(scratch) {
    const linkPath = path.join(scratch, "self-realpath", "bcquality");
    await fs.mkdir(linkPath, { recursive: true });
    const target = path.join(scratch, "target-points-back");
    await fs.symlink(linkPath, target, process.platform === "win32" ? "junction" : "dir");

    const messages = [];
    const logger = { info: () => undefined, error: (message) => messages.push(message) };

    await createBcqualityLink(linkPath, target, logger);

    const stats = await fs.lstat(linkPath);
    assert.ok(!stats.isSymbolicLink(), "the pre-existing real directory at linkPath must be left untouched");
    assert.ok(messages.some((message) => message.includes("itself")), "expected a clear log message about the self-reference");
}

// Regression guard for the pre-existing early-return: an already-correct junction must not be
// removed/recreated on a repeat call -- and must not be mistaken for a self-reference. A correct
// junction resolves to exactly its target, so a guard that resolves BOTH sides condemns every healthy
// link; this test's first version missed that by only counting "Linked" messages.
async function testExistingCorrectJunctionLeftAlone(scratch) {
    const target = path.join(scratch, "real-clone-noop");
    await fs.mkdir(target, { recursive: true });
    await fs.writeFile(path.join(target, "marker.txt"), "keep me");
    const linkPath = path.join(scratch, "noop-parent", "bcquality");

    const messages = [];
    const errors = [];
    const logger = { info: (message) => messages.push(message), error: (message) => errors.push(message) };

    await createBcqualityLink(linkPath, target, logger);
    await createBcqualityLink(linkPath, target, logger);

    const linkedMessages = messages.filter((message) => message.includes("Linked BCQuality"));
    const removedMessages = messages.filter((message) => message.includes("Removed BCQuality link"));
    assert.strictEqual(linkedMessages.length, 1, "junction must only be created once");
    assert.strictEqual(removedMessages.length, 0, "an unchanged target must never trigger a remove+recreate");
    assert.deepStrictEqual(errors, [], "a correct junction must never be reported as a self-reference");
    assert.ok(
        messages.some((message) => message.includes("already correct")),
        "the repeat call must take the already-correct path, not be refused by the self-reference guard"
    );
    assert.ok(await pathExists(path.join(linkPath, "marker.txt")), "the link must still reach the real target");
}

// The recorded link target keeps the drive letter as stored, while a resolved candidate can carry it
// lower-cased. On Windows those are the same path, and treating them as different makes the extension
// tear down and rebuild a healthy junction on every single run.
async function testCaseOnlyDifferenceIsNotAChange(scratch) {
    const target = path.join(scratch, "real-clone-case");
    await fs.mkdir(target, { recursive: true });
    const linkPath = path.join(scratch, "case-parent", "bcquality");

    const messages = [];
    const errors = [];
    const logger = { info: (message) => messages.push(message), error: (message) => errors.push(message) };

    await createBcqualityLink(linkPath, target, logger);
    const differentlyCased = process.platform === "win32"
        ? target.charAt(0).toLowerCase() + target.slice(1)
        : target;
    await createBcqualityLink(linkPath, differentlyCased, logger);

    assert.strictEqual(messages.filter((m) => m.includes("Linked BCQuality")).length, 1, "a case-only difference is not a changed target");
    assert.deepStrictEqual(errors, []);
}

async function pathExists(candidate) {
    try {
        await fs.access(candidate);
        return true;
    } catch {
        return false;
    }
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-self-ref-"));
    try {
        await testRefusesLiteralSelfReference(scratch);
        await testRefusesRealpathSelfReference(scratch);
        await testExistingCorrectJunctionLeftAlone(scratch);
        await testCaseOnlyDifferenceIsNotAChange(scratch);
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality self-reference guard tests passed."));
