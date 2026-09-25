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
const { createBcqualityLink, removeBcqualityLink } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-junction-"));
    const target = path.join(scratch, "real-clone");
    const linkPath = path.join(scratch, "link-parent", "bcquality");
    try {
        await fs.mkdir(target, { recursive: true });
        await fs.writeFile(path.join(target, "marker.txt"), "keep me");
        const logger = { info: () => undefined, error: () => undefined };

        await createBcqualityLink(linkPath, target, logger);
        const linkStats = await fs.lstat(linkPath);
        assert.ok(linkStats.isSymbolicLink(), "expected a junction/symlink to be created");

        // The critical assertion: removing the link must never recurse into its target.
        await removeBcqualityLink(linkPath, logger);
        await assert.rejects(() => fs.lstat(linkPath), "link should be gone after removal");

        const remainingEntries = await fs.readdir(target);
        assert.deepStrictEqual(remainingEntries, ["marker.txt"], "target directory listing must be unchanged");
        const remainingContent = await fs.readFile(path.join(target, "marker.txt"), "utf8");
        assert.strictEqual(remainingContent, "keep me", "target file content must be unchanged");

        // A non-link path must never be removed by this code path.
        const plainDir = path.join(scratch, "plain-dir");
        await fs.mkdir(plainDir, { recursive: true });
        await fs.writeFile(path.join(plainDir, "file.txt"), "still here");
        await removeBcqualityLink(plainDir, logger);
        const plainStats = await fs.lstat(plainDir);
        assert.ok(plainStats.isDirectory(), "a plain directory must never be removed");
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality junction safety tests passed."));
