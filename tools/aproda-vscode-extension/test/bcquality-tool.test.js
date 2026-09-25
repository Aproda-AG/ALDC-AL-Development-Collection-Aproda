const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

function makeVscodeMock({ bcqualityPath = "", workspaceFolders = [], onGetConfigurationKey } = {}) {
    return {
        workspace: {
            workspaceFolders,
            getConfiguration: (section) => ({
                get: (key, defaultValue) => {
                    if (onGetConfigurationKey) {
                        onGetConfigurationKey(section, key);
                    }
                    if (section === "aprodaAldc" && key === "bcquality.path") {
                        return bcqualityPath;
                    }
                    return defaultValue;
                }
            })
        }
    };
}

async function withTool(vscodeMock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
    };
    for (const mod of [
        "../dist/agent/bcqualityTool",
        "../dist/bcquality/resolve",
        "../dist/bcquality/aldcConfig",
        "../dist/bcquality/containment",
        "../dist/env/gitRoot",
        "../dist/config",
        "../dist/env/devRoot"
    ]) {
        delete require.cache[require.resolve(mod)];
    }
    try {
        const tool = require("../dist/agent/bcqualityTool");
        return await fn(tool);
    } finally {
        Module._load = originalLoad;
    }
}

async function makeVerifiedClone(root) {
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

async function testUnresolvedReturnsStructuredExplanation(scratch) {
    await withTool(makeVscodeMock({}), async ({ runBcqualityTool }) => {
        const output = await runBcqualityTool({ operation: "read", path: "skills/entry.md" });
        assert.strictEqual(output.status, "unresolved");
        assert.ok(output.message.length > 0, "must explain why, not just come back empty");
        assert.ok(Array.isArray(output.candidates) && output.candidates.length > 0, "must include the resolver's candidate verdicts");
        const sources = output.candidates.map((candidate) => candidate.source);
        for (const expected of ["setting", "workspaceFolder", "environment", "devRoot", "aldcYaml"]) {
            assert.ok(sources.includes(expected), `expected a candidate for ${expected}`);
        }
    });
}

async function testDisabledSaysSoExplicitly(scratch) {
    const repoRoot = path.join(scratch, "repo-disabled");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.writeFile(path.join(repoRoot, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");
    const clone = path.join(scratch, "clone-disabled");
    await makeVerifiedClone(clone);

    await withTool(
        makeVscodeMock({ bcqualityPath: clone, workspaceFolders: [{ uri: { fsPath: repoRoot } }] }),
        async ({ runBcqualityTool }) => {
            const output = await runBcqualityTool({ operation: "list", path: "." });
            assert.strictEqual(output.status, "disabled");
            assert.ok(/disabled/i.test(output.message), "must say explicitly that BCQuality is disabled");
        }
    );
}

// FIX 1: resolveBcquality()'s candidate probing reads config.ts's bcqualityPath() (the "bcquality.path" setting)
// exactly once per full resolution. Counting that specific read proves observably whether probing happened,
// not just what the tool returned.
async function testDisabledShortCircuitsBeforeProbing(scratch) {
    const repoRoot = path.join(scratch, "repo-disabled-2");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.writeFile(path.join(repoRoot, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");
    const clone = path.join(scratch, "clone-disabled-2");
    await makeVerifiedClone(clone);

    let probeReads = 0;
    await withTool(
        makeVscodeMock({
            bcqualityPath: clone,
            workspaceFolders: [{ uri: { fsPath: repoRoot } }],
            onGetConfigurationKey: (section, key) => {
                if (section === "aprodaAldc" && key === "bcquality.path") {
                    probeReads++;
                }
            }
        }),
        async ({ runBcqualityTool }) => {
            const output = await runBcqualityTool({ operation: "list", path: "." });
            assert.strictEqual(output.status, "disabled");
            assert.strictEqual(probeReads, 0, "the 'setting' candidate must never be probed when the project is disabled");
        }
    );

    // Control: the same instrumentation, without "enabled: false", must show the probe actually firing --
    // otherwise a probeReads===0 assertion above would be meaningless (e.g. if the mock were wired wrong).
    let controlProbeReads = 0;
    await withTool(
        makeVscodeMock({
            bcqualityPath: clone,
            onGetConfigurationKey: (section, key) => {
                if (section === "aprodaAldc" && key === "bcquality.path") {
                    controlProbeReads++;
                }
            }
        }),
        async ({ runBcqualityTool }) => {
            const output = await runBcqualityTool({ operation: "list", path: "." });
            assert.strictEqual(output.status, "ok");
            assert.ok(controlProbeReads > 0, "control: probing must fire when the project is not disabled");
        }
    );
}

// FIX 1: "Show BCQuality Status" reads the same resolveBcquality() output directly (not through the tool's
// short-circuit) and must keep exposing the full candidate chain even while BCQuality is disabled.
async function testStatusDataPathStillExposesChainWhenDisabled(scratch) {
    const repoRoot = path.join(scratch, "repo-disabled-3");
    await fs.mkdir(path.join(repoRoot, ".git"), { recursive: true });
    await fs.writeFile(path.join(repoRoot, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");
    const clone = path.join(scratch, "clone-disabled-3");
    await makeVerifiedClone(clone);

    await withTool(
        makeVscodeMock({ bcqualityPath: clone, workspaceFolders: [{ uri: { fsPath: repoRoot } }] }),
        async () => {
            const { resolveBcquality } = require("../dist/bcquality/resolve");
            const resolution = await resolveBcquality();
            assert.strictEqual(resolution.enabled, false);
            assert.ok(resolution.candidates.length > 0, "the candidate chain must still be populated when disabled");
            const settingCandidate = resolution.candidates.find((candidate) => candidate.source === "setting");
            assert.strictEqual(settingCandidate.verdict, "verified", "the resolver still verifies rungs even though the project is disabled");
        }
    );
}

async function testReadAndListWork(scratch) {
    const clone = path.join(scratch, "clone-ok");
    await makeVerifiedClone(clone);

    await withTool(makeVscodeMock({ bcqualityPath: clone }), async ({ runBcqualityTool }) => {
        const read = await runBcqualityTool({ operation: "read", path: "skills/entry.md" });
        assert.strictEqual(read.status, "ok");
        assert.strictEqual(read.content, "# entry");

        const list = await runBcqualityTool({ operation: "list", path: "." });
        assert.strictEqual(list.status, "ok");
        assert.deepStrictEqual(list.entries.map((entry) => entry.name), ["skills"]);
        assert.strictEqual(list.truncated, false);
    });
}

async function testPathEscapeRejected(scratch) {
    const clone = path.join(scratch, "clone-escape");
    await makeVerifiedClone(clone);
    await fs.writeFile(path.join(scratch, "outside.txt"), "TOP SECRET");

    await withTool(makeVscodeMock({ bcqualityPath: clone }), async ({ runBcqualityTool }) => {
        const output = await runBcqualityTool({ operation: "read", path: "../outside.txt" });
        assert.strictEqual(output.status, "invalidPath");
        assert.ok(!("content" in output), "an escaping path must never yield file content");
    });
}

async function testTooLargeFileRejected(scratch) {
    const clone = path.join(scratch, "clone-large");
    await makeVerifiedClone(clone);
    await fs.writeFile(path.join(clone, "big.md"), "x".repeat(300 * 1024));

    await withTool(makeVscodeMock({ bcqualityPath: clone }), async ({ runBcqualityTool, maxReadBytes }) => {
        const output = await runBcqualityTool({ operation: "read", path: "big.md" });
        assert.strictEqual(output.status, "tooLarge");
        assert.strictEqual(output.limitBytes, maxReadBytes);
    });
}

async function testListIsCapped(scratch) {
    const clone = path.join(scratch, "clone-many");
    await makeVerifiedClone(clone);
    for (let i = 0; i < 250; i++) {
        await fs.writeFile(path.join(clone, `file-${String(i).padStart(3, "0")}.md`), "content");
    }

    await withTool(makeVscodeMock({ bcqualityPath: clone }), async ({ runBcqualityTool, maxListEntries }) => {
        const output = await runBcqualityTool({ operation: "list", path: "." });
        assert.strictEqual(output.status, "ok");
        assert.strictEqual(output.truncated, true);
        assert.strictEqual(output.entries.length, maxListEntries);
        assert.strictEqual(output.totalCount, 251); // 250 files + the "skills" directory

        // FIX 2: ordering must stay deterministic (alphabetical) even though the cap is enforced without
        // materialising and sorting the full directory. "skills" (s) sorts after all 250 "file-*.md" (f)
        // entries, so the alphabetically-first 200 are exactly file-000.md .. file-199.md.
        const expected = Array.from({ length: maxListEntries }, (_, i) => `file-${String(i).padStart(3, "0")}.md`);
        assert.deepStrictEqual(output.entries.map((entry) => entry.name), expected);

        // Re-run to prove the ordering is not an artifact of directory-scan order on this one call.
        const second = await runBcqualityTool({ operation: "list", path: "." });
        assert.deepStrictEqual(second.entries.map((entry) => entry.name), expected, "listing must be deterministic across repeated calls");
    });
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-bcquality-tool-"));
    const previousEnv = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await testUnresolvedReturnsStructuredExplanation(scratch);
        await testDisabledSaysSoExplicitly(scratch);
        await testDisabledShortCircuitsBeforeProbing(scratch);
        await testStatusDataPathStillExposesChainWhenDisabled(scratch);
        await testReadAndListWork(scratch);
        await testPathEscapeRejected(scratch);
        await testTooLargeFileRejected(scratch);
        await testListIsCapped(scratch);
    } finally {
        if (previousEnv === undefined) {
            delete process.env.BCQUALITY_HOME;
        } else {
            process.env.BCQUALITY_HOME = previousEnv;
        }
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality tool tests passed."));
