// Item 1: the "release" channel path (VersionService.checkRelease / readAvailableReleaseTag),
// exercised against a REAL local git repository with real tags -- including a genuinely ANNOTATED
// tag, which `git ls-remote --tags` always reports as TWO lines (the tag object ref itself, plus a
// second "<sha> refs/tags/vX.Y.Z_aproda.N^{}" peeled line pointing at the underlying commit). The
// `$` anchor at the end of `versionPattern` (compare.ts) is what keeps that peeled line's ref value
// ("1.2.0_aproda.4^{}") from being treated as a valid, pickable layer version alongside the clean
// "1.2.0_aproda.4" -- this test asserts the picked `available` value is exactly the clean string.
const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");
const { execFileSync } = require("child_process");

const settings = {
    "source.mode": "managed",
    "channel": "release",
    "source.repositoryUrl": "",
    "branchName": ""
};
const vscodeMock = {
    workspace: {
        getConfiguration: () => ({
            get: (key, defaultValue) => (key in settings ? settings[key] : defaultValue)
        })
    },
    window: {
        createOutputChannel: () => ({ appendLine: () => { }, show: () => { }, dispose: () => { } })
    }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { VersionService } = require("../dist/version/service");
const { Logger } = require("../dist/log");
Module._load = originalLoad;

function git(cwd, args) {
    execFileSync("git", args, { cwd, stdio: "pipe" });
}

async function makeTaggedRemoteRepo(root) {
    await fs.mkdir(root, { recursive: true });
    git(root, ["init", "--quiet"]);
    git(root, ["config", "user.email", "test@example.com"]);
    git(root, ["config", "user.name", "Test"]);

    await fs.writeFile(path.join(root, "file.txt"), "first");
    git(root, ["add", "."]);
    git(root, ["commit", "--quiet", "-m", "first"]);
    // Lightweight tag -- one ls-remote line, no peeling.
    git(root, ["tag", "v1.0.0_aproda.1"]);
    // Non-conforming ref: must never be treated as a candidate at all.
    git(root, ["tag", "not-a-version-tag"]);

    await fs.writeFile(path.join(root, "file.txt"), "second");
    git(root, ["add", "."]);
    git(root, ["commit", "--quiet", "-m", "second"]);
    git(root, ["tag", "v1.1.0_aproda.2"]);
    // Genuinely ANNOTATED tag -- ls-remote reports both "refs/tags/v1.2.0_aproda.4" (the tag object)
    // AND "refs/tags/v1.2.0_aproda.4^{}" (the peeled commit) as separate lines. This is the newest,
    // highest-numbered tag in the repo.
    git(root, ["tag", "-a", "v1.2.0_aproda.4", "-m", "release 1.2.0_aproda.4"]);
}

function resetSettings() {
    settings["source.mode"] = "managed";
    settings["channel"] = "release";
    settings["source.repositoryUrl"] = "";
    settings["branchName"] = "";
}

async function writeLayerVersion(configRoot, layerVersion) {
    await fs.mkdir(configRoot, { recursive: true });
    await fs.writeFile(path.join(configRoot, "aldc.yaml"), `aproda:\n  layerVersion: ${layerVersion}\n`);
}

async function main() {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-version-release-"));
    const logger = new Logger();
    const service = new VersionService(logger);
    try {
        const remoteRoot = path.join(tempRoot, "remote");
        await makeTaggedRemoteRepo(remoteRoot);

        resetSettings();
        settings["source.repositoryUrl"] = remoteRoot;

        // Sanity: ls-remote against this fixture really does report the peeled line, so the assertions
        // below are testing something real, not an artifact of how the fixture happened to be built.
        const rawTags = execFileSync("git", ["ls-remote", "--tags", remoteRoot, "refs/tags/v*_aproda.*"], { cwd: tempRoot })
            .toString();
        assert.ok(rawTags.includes("refs/tags/v1.2.0_aproda.4^{}"), "fixture sanity: annotated tag must produce a peeled ^{} line");

        // outdated: installed is the oldest tag, latest is the annotated 1.2.0_aproda.4 -- and the
        // picked `available` string must be the CLEAN version, never contaminated with "^{}".
        const outdatedRoot = path.join(tempRoot, "outdated");
        await writeLayerVersion(outdatedRoot, "1.0.0_aproda.1");
        const outdated = await service.check(outdatedRoot);
        assert.strictEqual(outdated.status, "outdated");
        assert.strictEqual(outdated.installed, "1.0.0_aproda.1");
        assert.strictEqual(outdated.available, "1.2.0_aproda.4");
        assert.ok(!outdated.available.includes("^{}"), `available must not leak the peeled-ref suffix, got "${outdated.available}"`);
        assert.ok(!outdated.message.includes("^{}"), `user-facing message must not leak the peeled-ref suffix, got "${outdated.message}"`);

        // current: installed already equals the latest annotated tag's clean version string.
        const currentRoot = path.join(tempRoot, "current");
        await writeLayerVersion(currentRoot, "1.2.0_aproda.4");
        const current = await service.check(currentRoot);
        assert.strictEqual(current.status, "current");

        // ahead: installed is numerically greater than every tag in the remote.
        const aheadRoot = path.join(tempRoot, "ahead");
        await writeLayerVersion(aheadRoot, "9.9.9_aproda.9");
        const ahead = await service.check(aheadRoot);
        assert.strictEqual(ahead.status, "ahead");
        assert.strictEqual(ahead.available, "1.2.0_aproda.4");

        // invalid: the installed value is not layer-version-shaped at all.
        const invalidRoot = path.join(tempRoot, "invalid");
        await writeLayerVersion(invalidRoot, "not-a-version");
        const invalid = await service.check(invalidRoot);
        assert.strictEqual(invalid.status, "invalid");

        // unavailable: a real repo with zero conforming tags -- ls-remote succeeds but yields nothing
        // to pick from (must not be confused with a git/network failure, but reads the same to the caller).
        const emptyRemoteRoot = path.join(tempRoot, "empty-remote");
        await fs.mkdir(emptyRemoteRoot, { recursive: true });
        git(emptyRemoteRoot, ["init", "--quiet"]);
        git(emptyRemoteRoot, ["config", "user.email", "test@example.com"]);
        git(emptyRemoteRoot, ["config", "user.name", "Test"]);
        await fs.writeFile(path.join(emptyRemoteRoot, "file.txt"), "only");
        git(emptyRemoteRoot, ["add", "."]);
        git(emptyRemoteRoot, ["commit", "--quiet", "-m", "only"]);
        settings["source.repositoryUrl"] = emptyRemoteRoot;
        const unavailableRoot = path.join(tempRoot, "unavailable");
        await writeLayerVersion(unavailableRoot, "1.0.0_aproda.1");
        const unavailable = await service.check(unavailableRoot);
        assert.strictEqual(unavailable.status, "unavailable");
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("Release channel version detection tests passed."));
