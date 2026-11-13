// createBcqualityLink on a network drive: EEXIST from an unreadable junction is a warning, never a throw (E-006 e2e-05).
const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const vscodeMock = {
    workspace: { textDocuments: [], workspaceFolders: [], getConfiguration: () => ({ get: (_key, defaultValue) => defaultValue }) },
    ConfigurationTarget: { Global: 1 }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { createBcqualityLink } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

const makeLogger = () => {
    const lines = [];
    return { lines, info: (m) => lines.push(`INFO: ${m}`), warn: (m) => lines.push(`WARNING: ${m}`), error: (m) => lines.push(`ERROR: ${m}`) };
};

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-eexist-"));
    const target = path.join(scratch, "real-clone");
    try {
        await fs.mkdir(target, { recursive: true });

        // Healthy: unchanged info line, no warning.
        const healthy = makeLogger();
        const healthyLink = path.join(scratch, "ok", "bcquality");
        await createBcqualityLink(healthyLink, target, healthy);
        assert.deepStrictEqual(healthy.lines, [`INFO: Linked BCQuality: ${healthyLink} -> ${target}`]);

        // A conflicting, unreadable-as-link entry: symlink raises EEXIST -> warning, no throw, nothing deleted.
        const conflictLink = path.join(scratch, "conflict", "bcquality");
        await fs.mkdir(conflictLink, { recursive: true });
        await fs.writeFile(path.join(conflictLink, "keep.txt"), "keep");
        const conflict = makeLogger();
        await createBcqualityLink(conflictLink, target, conflict);
        assert.strictEqual(conflict.lines.length, 1);
        assert.ok(conflict.lines[0].startsWith("WARNING: BCQuality link not created"), conflict.lines[0]);
        assert.ok(conflict.lines[0].includes(`cmd /c rmdir "${conflictLink}"`));
        assert.strictEqual(await fs.readFile(path.join(conflictLink, "keep.txt"), "utf8"), "keep", "nothing is deleted");

        // Created but not readable: warning instead of the info line.
        const realSymlink = fs.symlink;
        const realReaddir = fs.readdir;
        const unreadableLink = path.join(scratch, "unreadable", "bcquality");
        fs.readdir = async (p, ...rest) => {
            if (p === unreadableLink) { throw Object.assign(new Error("EIO"), { code: "EIO" }); }
            return realReaddir.call(fs, p, ...rest);
        };
        try {
            const unreadable = makeLogger();
            await createBcqualityLink(unreadableLink, target, unreadable);
            assert.strictEqual(unreadable.lines.length, 1);
            assert.ok(unreadable.lines[0].startsWith("WARNING: BCQuality link created but not readable"), unreadable.lines[0]);
        } finally {
            fs.readdir = realReaddir;
        }

        // Other symlink errors still propagate.
        fs.symlink = async () => { throw Object.assign(new Error("denied"), { code: "EPERM" }); };
        try {
            await assert.rejects(() => createBcqualityLink(path.join(scratch, "perm", "bcquality"), target, makeLogger()), /denied/);
        } finally {
            fs.symlink = realSymlink;
        }
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality link EEXIST tests passed."));
