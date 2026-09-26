const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

// B-30: on Windows, npm has no .exe (only npm.cmd); spawn without shell:true needs the exact
// extension to resolve it, or it fails with ENOENT even though npm works fine in a terminal.
// Asserts the identity of what is spawned, not merely that the command "works".

function makeHarness(repositoryRoot) {
    const runCalls = [];
    const vscodeMock = {
        window: {
            withProgress: async (_options, task) => task({ report: () => undefined }),
            showErrorMessage: async () => undefined,
            showWarningMessage: async () => undefined,
            showInformationMessage: async () => undefined
        },
        ProgressLocation: { Notification: 15 }
    };
    const gitRootMock = {
        resolveTargetRepo: async () => repositoryRoot
    };
    const processMock = {
        run: async (command, args, options) => {
            runCalls.push({ command, args, options });
            if (command === "node") {
                return { code: 0, stdout: "COMPLIANT (0 warning(s))", stderr: "" };
            }
            return { code: 0, stdout: "", stderr: "" };
        }
    };
    return { vscodeMock, gitRootMock, processMock, runCalls };
}

async function withValidate(harness, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        if (request === "vscode") { return harness.vscodeMock; }
        if (parent && parent.filename.includes("validate")) {
            if (request === "../env/gitRoot") { return harness.gitRootMock; }
            if (request === "../process") { return harness.processMock; }
        }
        return originalLoad.call(this, request, parent, isMain);
    };
    delete require.cache[require.resolve("../dist/commands/validate")];
    try {
        return await fn(require("../dist/commands/validate"));
    } finally {
        Module._load = originalLoad;
    }
}

const logger = { info: () => undefined, error: () => undefined, show: () => undefined };

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-validate-npm-spawn-"));
    try {
        const repositoryRoot = path.join(scratch, "project");
        const validatorRoot = path.join(repositoryRoot, ".github", "tools", "aldc-validate");
        await fs.mkdir(validatorRoot, { recursive: true });
        await fs.writeFile(path.join(validatorRoot, "index.js"), "// stub validator\n");
        // node_modules/js-yaml intentionally absent, forcing the npm install branch.

        const harness = makeHarness(repositoryRoot);
        await withValidate(harness, async ({ validateInstallation, npmExecutable }) => {
            // Asserted for both platforms explicitly: mirroring `process.platform` here would make the
            // test agree with the code on a non-Windows runner without ever exercising the win32 branch.
            assert.strictEqual(npmExecutable("win32"), "npm.cmd");
            assert.strictEqual(npmExecutable("linux"), "npm");
            assert.strictEqual(npmExecutable("darwin"), "npm");
            await validateInstallation(logger);
        });

        assert.strictEqual(harness.runCalls.length, 2, "expected an npm install call followed by a node validator call");
        const [installCall, validatorCall] = harness.runCalls;

        const expectedNpmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
        assert.strictEqual(installCall.command, expectedNpmCommand);
        assert.deepStrictEqual(installCall.args, ["install", "--omit=dev", "--no-package-lock"]);
        assert.strictEqual(installCall.options.cwd, validatorRoot);

        // The node call must remain unshimmed: node ships an .exe on Windows, no rewrite is needed there.
        assert.strictEqual(validatorCall.command, "node");
        assert.deepStrictEqual(validatorCall.args, [path.join(validatorRoot, "index.js")]);
        assert.strictEqual(validatorCall.options.cwd, repositoryRoot);

        // The fix must be local to this call site: process.ts itself must not gain a shell option,
        // which would change argument quoting for every other caller (e.g. git with repository URLs).
        const processSource = await fs.readFile(path.join(__dirname, "..", "dist", "process.js"), "utf8");
        assert.ok(!/shell/i.test(processSource), "run() must stay shell-free; the fix belongs at the npm call site only");
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("Validate npm spawn shape tests passed."));
