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

async function makeRemoteRepo(root) {
    await fs.mkdir(root, { recursive: true });
    git(root, ["init", "--quiet"]);
    git(root, ["config", "user.email", "test@example.com"]);
    git(root, ["config", "user.name", "Test"]);
    await fs.writeFile(path.join(root, "file.txt"), "first");
    git(root, ["add", "."]);
    git(root, ["commit", "--quiet", "-m", "first"]);
    const firstSha = execFileSync("git", ["rev-parse", "HEAD"], { cwd: root }).toString().trim();
    const defaultBranch = execFileSync("git", ["symbolic-ref", "--short", "HEAD"], { cwd: root }).toString().trim();
    git(root, ["branch", "aproda"]);
    git(root, ["branch", "pilot"]);

    await fs.writeFile(path.join(root, "file.txt"), "second");
    git(root, ["add", "."]);
    git(root, ["commit", "--quiet", "-m", "second"]);
    git(root, ["checkout", "--quiet", "aproda"]);
    git(root, ["merge", "--quiet", defaultBranch, "--ff-only"]);
    const secondSha = execFileSync("git", ["rev-parse", "aproda"], { cwd: root }).toString().trim();
    git(root, ["checkout", "--quiet", "pilot"]);
    git(root, ["merge", "--quiet", defaultBranch, "--ff-only"]);

    return { firstSha, secondSha };
}

async function writeAppliedRef(configRoot, appliedRef) {
    await fs.mkdir(configRoot, { recursive: true });
    const body = appliedRef === undefined ? "aproda:\n  layerVersion: 1.0.0_aproda.1\n" : `aproda:\n  appliedRef: ${appliedRef}\n`;
    await fs.writeFile(path.join(configRoot, "aldc.yaml"), body);
}

function resetSettings() {
    settings["source.mode"] = "managed";
    settings["channel"] = "release";
    settings["source.repositoryUrl"] = "";
    settings["branchName"] = "";
}

async function main() {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-version-channels-"));
    const logger = new Logger();
    const service = new VersionService(logger);
    try {
        const remoteRoot = path.join(tempRoot, "remote");
        const { firstSha, secondSha } = await makeRemoteRepo(remoteRoot);

        // edge: appliedRef differs from origin/aproda's tip -> outdated, with shortened display SHAs.
        resetSettings();
        settings["channel"] = "edge";
        settings["source.repositoryUrl"] = remoteRoot;
        const edgeOutdatedRoot = path.join(tempRoot, "edge-outdated");
        await writeAppliedRef(edgeOutdatedRoot, firstSha);
        const edgeOutdated = await service.check(edgeOutdatedRoot);
        assert.strictEqual(edgeOutdated.status, "outdated");
        assert.strictEqual(edgeOutdated.installed, firstSha.slice(0, 8));
        assert.strictEqual(edgeOutdated.available, secondSha.slice(0, 8));

        // edge: appliedRef matches the tip -> current.
        const edgeCurrentRoot = path.join(tempRoot, "edge-current");
        await writeAppliedRef(edgeCurrentRoot, secondSha);
        const edgeCurrent = await service.check(edgeCurrentRoot);
        assert.strictEqual(edgeCurrent.status, "current");

        // edge: never invokes isLayerVersion/compareLayerVersions -> a non-version-shaped appliedRef
        // must never surface as "invalid" on a SHA channel.
        const edgeGarbageRoot = path.join(tempRoot, "edge-garbage");
        await writeAppliedRef(edgeGarbageRoot, "totally-not-a-sha");
        const edgeGarbage = await service.check(edgeGarbageRoot);
        assert.notStrictEqual(edgeGarbage.status, "invalid");
        assert.strictEqual(edgeGarbage.status, "outdated");

        // branch: appliedRef missing (first switch to the channel) -> "unknown", not current/invalid,
        // and no update is invented.
        resetSettings();
        settings["channel"] = "branch";
        settings["source.repositoryUrl"] = remoteRoot;
        settings["branchName"] = "pilot";
        const branchUnknownRoot = path.join(tempRoot, "branch-unknown");
        await fs.mkdir(branchUnknownRoot, { recursive: true });
        await fs.writeFile(path.join(branchUnknownRoot, "aldc.yaml"), "aproda:\n  layerVersion: 1.0.0_aproda.1\n");
        const branchUnknown = await service.check(branchUnknownRoot);
        assert.strictEqual(branchUnknown.status, "unknown");
        assert.strictEqual(branchUnknown.installed, undefined);

        // branch: repointed without a fresh apply -> stale appliedRef mismatches the new tip -> outdated,
        // not silently "current".
        const branchStaleRoot = path.join(tempRoot, "branch-stale");
        await writeAppliedRef(branchStaleRoot, firstSha);
        const branchStale = await service.check(branchStaleRoot);
        assert.strictEqual(branchStale.status, "outdated");

        // branch: ls-remote succeeds but returns nothing for a deleted/renamed branch -> "unavailable",
        // never "current" (B-6).
        settings["branchName"] = "does-not-exist";
        const branchDeletedRoot = path.join(tempRoot, "branch-deleted");
        await writeAppliedRef(branchDeletedRoot, firstSha);
        const branchDeleted = await service.check(branchDeletedRoot);
        assert.strictEqual(branchDeleted.status, "unavailable");

        // git/network failure (repository path is not a git repository at all) -> "unavailable" too.
        settings["branchName"] = "pilot";
        settings["source.repositoryUrl"] = path.join(tempRoot, "not-a-repo");
        const gitFailureRoot = path.join(tempRoot, "git-failure");
        await writeAppliedRef(gitFailureRoot, firstSha);
        const gitFailure = await service.check(gitFailureRoot);
        assert.strictEqual(gitFailure.status, "unavailable");

        // pinned channel never reports an update, regardless of what is installed.
        resetSettings();
        settings["channel"] = "pinned";
        const pinnedRoot = path.join(tempRoot, "pinned");
        await fs.mkdir(pinnedRoot, { recursive: true });
        await fs.writeFile(path.join(pinnedRoot, "aldc.yaml"), "aproda:\n  layerVersion: 0.0.1_aproda.1\n");
        const pinnedResult = await service.check(pinnedRoot);
        assert.strictEqual(pinnedResult.status, "current");

        // localFork source mode never reports an update, regardless of channel.
        resetSettings();
        settings["source.mode"] = "localFork";
        settings["channel"] = "edge";
        const localForkRoot = path.join(tempRoot, "local-fork");
        await fs.mkdir(localForkRoot, { recursive: true });
        await fs.writeFile(path.join(localForkRoot, "aldc.yaml"), "aproda:\n  layerVersion: 0.0.1_aproda.1\n");
        const localForkResult = await service.check(localForkRoot);
        assert.strictEqual(localForkResult.status, "current");

        // The "is it installed at all" gate still runs first, for every channel.
        resetSettings();
        settings["channel"] = "edge";
        settings["source.repositoryUrl"] = remoteRoot;
        const notInstalledRoot = path.join(tempRoot, "not-installed");
        await fs.mkdir(notInstalledRoot, { recursive: true });
        const notInstalledResult = await service.check(notInstalledRoot);
        assert.strictEqual(notInstalledResult.status, "notInstalled");
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("Version service channel detection tests passed."));
