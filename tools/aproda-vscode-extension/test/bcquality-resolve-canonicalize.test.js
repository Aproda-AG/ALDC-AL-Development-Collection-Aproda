const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

function makeVscodeMock({ workspaceFolders = [] } = {}) {
    return {
        workspace: {
            workspaceFolders,
            getConfiguration: () => ({ get: (_key, defaultValue) => defaultValue })
        }
    };
}

async function withResolver(vscodeMock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of ["../dist/bcquality/resolve", "../dist/bcquality/aldcConfig", "../dist/env/gitRoot", "../dist/config", "../dist/env/devRoot"]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        const { resolveBcquality } = require("../dist/bcquality/resolve");
        return await fn(resolveBcquality);
    } finally {
        Module._load = originalLoad;
    }
}

async function makeVerifiedRoot(root) {
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

// B-28 regression: a candidate reached through a junction (e.g. the .external/bcquality wrapper) must
// canonicalise to the real clone, never the junction path -- otherwise that junction path gets written
// into the Global setting and later handed back to createBcqualityLink as its own target.
async function testJunctionCanonicalisesToRealClone(scratch) {
    const repoRoot = path.join(scratch, "repo-canon-1");
    await fs.mkdir(repoRoot, { recursive: true });
    const realClone = path.join(scratch, "real-clone-canon-1");
    await makeVerifiedRoot(realClone);
    // os.tmpdir() can return an 8.3 short-name path segment on Windows; realpath() always expands it to the
    // long form, so the expected value for comparison must go through the same normalisation.
    const realCloneCanonical = path.resolve((await fs.realpath(realClone)).replace(/^\\\\\?\\/, ""));

    // Matches the workspaceFolder wrapper-subfolder probe (<folder>/bcquality).
    const junctionPath = path.join(repoRoot, "bcquality");
    await fs.symlink(realClone, junctionPath, process.platform === "win32" ? "junction" : "dir");

    const previousEnv = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await withResolver(makeVscodeMock({ workspaceFolders: [{ uri: { fsPath: repoRoot } }] }), async (resolveBcquality) => {
            const resolution = await resolveBcquality();
            assert.strictEqual(resolution.verified, true);
            assert.strictEqual(resolution.resolvedFrom, "workspaceFolder");
            assert.strictEqual(
                path.resolve(resolution.root),
                realCloneCanonical,
                `resolved root must be the real clone, not the junction path (got ${resolution.root})`
            );
            assert.notStrictEqual(
                path.resolve(resolution.root),
                path.resolve(junctionPath),
                "resolved root must not equal the junction path"
            );

            const winner = resolution.candidates.find((candidate) => candidate.source === "workspaceFolder" && candidate.verdict === "verified");
            assert.ok(winner, "expected a verified workspaceFolder candidate");
            assert.strictEqual(path.resolve(winner.path), path.resolve(junctionPath), "candidate.path must still report the probed (junction) path");
            assert.strictEqual(path.resolve(winner.realPath), realCloneCanonical, "candidate.realPath must report the real clone");
        });
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
    }
}

// A verified candidate reached directly (no link involved) must not gain a spurious realPath.
async function testDirectCandidateHasNoRealPath(scratch) {
    const directClone = path.join(scratch, "direct-clone-canon-2");
    await makeVerifiedRoot(directClone);

    const previousEnv = process.env.BCQUALITY_HOME;
    process.env.BCQUALITY_HOME = directClone;
    try {
        await withResolver(makeVscodeMock({}), async (resolveBcquality) => {
            const resolution = await resolveBcquality();
            assert.strictEqual(resolution.resolvedFrom, "environment");
            assert.strictEqual(path.resolve(resolution.root), path.resolve(directClone));
            const winner = resolution.candidates.find((candidate) => candidate.source === "environment");
            assert.strictEqual(winner.realPath, undefined, "a directly-reached clone must not report a realPath");
        });
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
    }
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-canon-"));
    try {
        await testJunctionCanonicalisesToRealClone(scratch);
        await testDirectCandidateHasNoRealPath(scratch);
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality resolve canonicalisation tests passed."));
