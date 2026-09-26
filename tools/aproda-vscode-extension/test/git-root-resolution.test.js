const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

let quickPickCallCount = 0;
let quickPickReturnValue;
let errorMessages = [];
const vscodeMock = {
    workspace: {
        workspaceFolders: []
    },
    window: {
        showQuickPick: async (items) => {
            quickPickCallCount += 1;
            if (quickPickReturnValue !== undefined) {
                return quickPickReturnValue;
            }
            return items[0];
        },
        showErrorMessage: (message) => {
            errorMessages.push(message);
            return Promise.resolve(undefined);
        }
    }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { resolveTargetRepo } = require("../dist/env/gitRoot");
Module._load = originalLoad;

async function makeGitRoot(root) {
    await fs.mkdir(path.join(root, ".git"), { recursive: true });
}

async function makeBcqualityClone(root) {
    await makeGitRoot(root);
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

function asWorkspaceFolder(fsPath) {
    return { uri: { fsPath } };
}

async function withFreshResolver(fn) {
    quickPickCallCount = 0;
    quickPickReturnValue = undefined;
    errorMessages = [];
    return fn();
}

// FIX 3, case 1: one of two git roots is a BCQuality clone -> excluded automatically, no prompt.
async function testBcqualityCloneExcludedAutomatically(scratch) {
    const projectRoot = path.join(scratch, "case1-project");
    const bcqualityRoot = path.join(scratch, "case1-bcquality");
    await makeGitRoot(projectRoot);
    await makeBcqualityClone(bcqualityRoot);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(projectRoot), asWorkspaceFolder(bcqualityRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(path.resolve(resolved), path.resolve(projectRoot), "must resolve to the non-clone repository");
        assert.strictEqual(quickPickCallCount, 0, "must not prompt when only one candidate is not a BCQuality clone");
    });
}

// FIX 3, case 2: two non-clone git roots, one carries aldc.yaml -> resolved automatically, no prompt.
async function testAldcYamlBreaksAmbiguity(scratch) {
    const configuredRoot = path.join(scratch, "case2-configured");
    const otherRoot = path.join(scratch, "case2-other");
    await makeGitRoot(configuredRoot);
    await fs.writeFile(path.join(configuredRoot, "aldc.yaml"), "toolkitRoot: .\n");
    await makeGitRoot(otherRoot);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(configuredRoot), asWorkspaceFolder(otherRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(path.resolve(resolved), path.resolve(configuredRoot), "must resolve to the repository declaring aldc.yaml");
        assert.strictEqual(quickPickCallCount, 0, "must not prompt when exactly one candidate declares aldc.yaml");
    });
}

// FIX 3, case 3: a single git root with no aldc.yaml at all -> first-time initialization, no prompt.
async function testFirstTimeInitializationNoPrompt(scratch) {
    const onlyRoot = path.join(scratch, "case3-only");
    await makeGitRoot(onlyRoot);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(onlyRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(path.resolve(resolved), path.resolve(onlyRoot));
        assert.strictEqual(quickPickCallCount, 0, "a brand-new project with a single git root must never prompt");
    });
}

// FIX 3, case 4: genuinely ambiguous (two non-clone roots, neither declaring aldc.yaml) -> must still prompt.
async function testGenuineAmbiguityStillPrompts(scratch) {
    const rootA = path.join(scratch, "case4-a");
    const rootB = path.join(scratch, "case4-b");
    await makeGitRoot(rootA);
    await makeGitRoot(rootB);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(rootA), asWorkspaceFolder(rootB)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.ok(resolved, "a selection must still be returned once the user picks one");
        assert.strictEqual(quickPickCallCount, 1, "genuinely ambiguous candidates must still prompt exactly once");
    });
}

// FIX 1 (reviewer reproduction): a BCQuality clone carrying its own aldc.yaml, declaring a custom
// entryPoint that does not exist in it, must still be detected as a clone via the fixed default marker.
async function testCloneWithForgedAldcYamlEntryPointStillDetected(scratch) {
    const projectRoot = path.join(scratch, "repro-project");
    const bcqualityRoot = path.join(scratch, "repro-bcquality");
    await makeGitRoot(projectRoot);
    await makeBcqualityClone(bcqualityRoot);
    await fs.writeFile(path.join(bcqualityRoot, "aldc.yaml"), "external:\n  bcquality:\n    entryPoint: docs/other-entry.md\n");
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(projectRoot), asWorkspaceFolder(bcqualityRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(path.resolve(resolved), path.resolve(projectRoot), "must resolve to the project, not the clone with a forged entryPoint");
        assert.strictEqual(quickPickCallCount, 0, "must not prompt: the clone is excluded regardless of its own aldc.yaml");
    });
}

// FIX 2, case A: the only open repository is a BCQuality clone -> must not be returned, must show an error.
async function testSingleRootCloneRefused(scratch) {
    const bcqualityRoot = path.join(scratch, "single-clone-only");
    await makeBcqualityClone(bcqualityRoot);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(bcqualityRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(resolved, undefined, "a lone BCQuality clone must never be returned as the target repository");
        assert.strictEqual(quickPickCallCount, 0, "must not prompt when there is nothing to choose between");
        assert.strictEqual(errorMessages.length, 1, "must show exactly one error explaining why nothing was resolved");
    });
}

// FIX 2, case B: the only open repository is a plain project without aldc.yaml -> first-time init still works.
async function testSingleRootPlainProjectStillResolves(scratch) {
    const onlyRoot = path.join(scratch, "single-plain-only");
    await makeGitRoot(onlyRoot);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(onlyRoot)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(path.resolve(resolved), path.resolve(onlyRoot));
        assert.strictEqual(quickPickCallCount, 0, "a single plain project must resolve without a prompt");
        assert.strictEqual(errorMessages.length, 0, "a single plain project must not raise an error");
    });
}

// Every candidate is a clone: a picker would offer only wrong answers, so it must refuse like the single-root case.
async function testAllCandidatesAreClonesRefused(scratch) {
    const firstClone = path.join(scratch, "all-clones-a");
    const secondClone = path.join(scratch, "all-clones-b");
    await makeBcqualityClone(firstClone);
    await makeBcqualityClone(secondClone);
    vscodeMock.workspace.workspaceFolders = [asWorkspaceFolder(firstClone), asWorkspaceFolder(secondClone)];

    await withFreshResolver(async () => {
        const resolved = await resolveTargetRepo();
        assert.strictEqual(resolved, undefined, "a set consisting only of BCQuality clones must never resolve to one of them");
        assert.strictEqual(quickPickCallCount, 0, "must not offer a picker whose every option is invalid");
        assert.strictEqual(errorMessages.length, 1, "must explain why nothing was resolved");
    });
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-gitroot-"));
    try {
        await testBcqualityCloneExcludedAutomatically(scratch);
        await testAldcYamlBreaksAmbiguity(scratch);
        await testFirstTimeInitializationNoPrompt(scratch);
        await testGenuineAmbiguityStillPrompts(scratch);
        await testCloneWithForgedAldcYamlEntryPointStillDetected(scratch);
        await testSingleRootCloneRefused(scratch);
        await testSingleRootPlainProjectStillResolves(scratch);
        await testAllCandidatesAreClonesRefused(scratch);
    } finally {
        vscodeMock.workspace.workspaceFolders = [];
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("Git root resolution tests passed."));
