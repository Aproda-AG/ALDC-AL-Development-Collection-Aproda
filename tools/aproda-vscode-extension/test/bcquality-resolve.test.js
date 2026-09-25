const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

function makeVscodeMock({ bcqualityPath = "", devRootPath = "", workspaceFolders = [] } = {}) {
    return {
        workspace: {
            workspaceFolders,
            getConfiguration: (section) => ({
                get: (key, defaultValue) => {
                    if (section === "aprodaAldc") {
                        if (key === "bcquality.path") {
                            return bcqualityPath;
                        }
                        if (key === "devRoot") {
                            return devRootPath;
                        }
                    }
                    return defaultValue;
                }
            })
        }
    };
}

async function withResolver(vscodeMock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    delete require.cache[require.resolve("../dist/bcquality/resolve")];
    delete require.cache[require.resolve("../dist/bcquality/aldcConfig")];
    delete require.cache[require.resolve("../dist/env/gitRoot")];
    delete require.cache[require.resolve("../dist/config")];
    delete require.cache[require.resolve("../dist/env/devRoot")];
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

async function testSettingWins(scratch) {
    const settingRoot = path.join(scratch, "setting-clone");
    const devRootPath = path.join(scratch, "dev-root");
    const devRootClone = path.join(devRootPath, "BCQuality-Aproda");
    await makeVerifiedRoot(settingRoot);
    await makeVerifiedRoot(devRootClone);

    await withResolver(makeVscodeMock({ bcqualityPath: settingRoot, devRootPath }), async (resolveBcquality) => {
        const resolution = await resolveBcquality();
        assert.strictEqual(resolution.verified, true);
        assert.strictEqual(resolution.resolvedFrom, "setting");
        assert.strictEqual(path.resolve(resolution.root), path.resolve(settingRoot));
    });
}

async function testUnverifiedPathRejectedNextRungTried(scratch) {
    const settingRoot = path.join(scratch, "setting-empty");
    const devRootPath = path.join(scratch, "dev-root-2");
    const devRootClone = path.join(devRootPath, "BCQuality-Aproda");
    await fs.mkdir(settingRoot, { recursive: true }); // present, but no entry point
    await makeVerifiedRoot(devRootClone);

    await withResolver(makeVscodeMock({ bcqualityPath: settingRoot, devRootPath }), async (resolveBcquality) => {
        const resolution = await resolveBcquality();
        const settingCandidate = resolution.candidates.find((candidate) => candidate.source === "setting");
        assert.strictEqual(settingCandidate.verdict, "noEntryPoint");
        assert.strictEqual(resolution.verified, true);
        assert.strictEqual(resolution.resolvedFrom, "devRoot");
        assert.strictEqual(path.resolve(resolution.root), path.resolve(devRootClone));
    });
}

// Regression guard: the existing tests above only prove "setting" beats "devRoot". These two prove the
// relative order of the remaining three rungs, so a reordering among them is caught.
async function testWorkspaceFolderBeatsEnvironmentAndAldcYaml(scratch) {
    const repoRoot = path.join(scratch, "repo-precedence-1");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    const workspaceClone = path.join(repoRoot, "bcquality"); // matches the workspaceFolder wrapper-subfolder probe
    await makeVerifiedRoot(workspaceClone);

    const envClone = path.join(scratch, "env-clone-1");
    await makeVerifiedRoot(envClone);
    const aldcYamlClone = path.join(scratch, "aldcyaml-clone-1");
    await makeVerifiedRoot(aldcYamlClone);
    await fs.writeFile(
        path.join(repoRoot, "aldc.yaml"),
        `external:\n  bcquality:\n    enabled: true\n    home: '${aldcYamlClone.replace(/'/g, "''")}'\n`
    );

    const previousEnv = process.env.BCQUALITY_HOME;
    process.env.BCQUALITY_HOME = envClone;
    try {
        await withResolver(makeVscodeMock({ workspaceFolders: [{ uri: { fsPath: repoRoot } }] }), async (resolveBcquality) => {
            const resolution = await resolveBcquality();
            assert.strictEqual(resolution.resolvedFrom, "workspaceFolder");
            assert.strictEqual(path.resolve(resolution.root), path.resolve(workspaceClone));
        });
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
    }
}

async function testEnvironmentBeatsAldcYaml(scratch) {
    const repoRoot = path.join(scratch, "repo-precedence-2");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    // Deliberately no entry.md at the folder root or its "bcquality" subfolder: the workspaceFolder rung
    // must stay unverified so this test isolates the environment-vs-aldcYaml ordering.

    const envClone = path.join(scratch, "env-clone-2");
    await makeVerifiedRoot(envClone);
    const aldcYamlClone = path.join(scratch, "aldcyaml-clone-2");
    await makeVerifiedRoot(aldcYamlClone);
    await fs.writeFile(
        path.join(repoRoot, "aldc.yaml"),
        `external:\n  bcquality:\n    enabled: true\n    home: '${aldcYamlClone.replace(/'/g, "''")}'\n`
    );

    const previousEnv = process.env.BCQUALITY_HOME;
    process.env.BCQUALITY_HOME = envClone;
    try {
        await withResolver(makeVscodeMock({ workspaceFolders: [{ uri: { fsPath: repoRoot } }] }), async (resolveBcquality) => {
            const resolution = await resolveBcquality();
            const workspaceFolderCandidates = resolution.candidates.filter((candidate) => candidate.source === "workspaceFolder");
            assert.ok(
                workspaceFolderCandidates.every((candidate) => candidate.verdict !== "verified"),
                "workspaceFolder rung must not verify in this fixture"
            );
            assert.strictEqual(resolution.resolvedFrom, "environment");
            assert.strictEqual(path.resolve(resolution.root), path.resolve(envClone));
        });
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
    }
}

async function testNothingVerifies() {
    await withResolver(makeVscodeMock({}), async (resolveBcquality) => {
        const resolution = await resolveBcquality();
        assert.strictEqual(resolution.verified, false);
        assert.strictEqual(resolution.root, undefined);
        assert.strictEqual(resolution.resolvedFrom, undefined);
        const sources = resolution.candidates.map((candidate) => candidate.source);
        for (const expected of ["setting", "workspaceFolder", "environment", "devRoot", "aldcYaml"]) {
            assert.ok(sources.includes(expected), `expected candidate for ${expected}`);
        }
        assert.ok(resolution.candidates.every((candidate) => candidate.verdict === "notSet"));
    });
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-resolve-"));
    const previousBcqualityHome = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await testSettingWins(scratch);
        await testUnverifiedPathRejectedNextRungTried(scratch);
        await testWorkspaceFolderBeatsEnvironmentAndAldcYaml(scratch);
        await testEnvironmentBeatsAldcYaml(scratch);
        await testNothingVerifies();
    } finally {
        if (previousBcqualityHome === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousBcqualityHome;
        }
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality resolver tests passed."));
