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
        await withValidate(harness, async ({ validateInstallation, npmInstallCommand }) => {
            // The whole invocation must be one constant string: under a shell, anything concatenated
            // into it would stop being an argument and start being shell syntax.
            assert.strictEqual(npmInstallCommand, "npm install --omit=dev --no-package-lock");
            await validateInstallation(logger);
        });

        assert.strictEqual(harness.runCalls.length, 2, "expected an npm install call followed by a node validator call");
        const [installCall, validatorCall] = harness.runCalls;

        // Node >= 18.20 refuses to spawn a .cmd shim without a shell (EINVAL), and npm has no .exe on
        // Windows -- so the shell is required here, and the argument array must stay empty.
        assert.strictEqual(installCall.command, "npm install --omit=dev --no-package-lock");
        assert.deepStrictEqual(installCall.args, []);
        assert.strictEqual(installCall.options.shell, true);
        assert.strictEqual(installCall.options.cwd, validatorRoot);

        // The node call must remain unshimmed and unshelled: node ships an .exe on Windows, and a shell
        // would change how the validator path argument is quoted.
        assert.strictEqual(validatorCall.command, "node");
        assert.deepStrictEqual(validatorCall.args, [path.join(validatorRoot, "index.js")]);
        assert.strictEqual(validatorCall.options.cwd, repositoryRoot);
        assert.notStrictEqual(validatorCall.options.shell, true, "the validator call must not run under a shell");

        // The shell must stay opt-in per call: a default-on shell would silently change argument
        // quoting for every caller, including git calls carrying repository URLs and paths.
        const processSource = await fs.readFile(path.join(__dirname, "..", "dist", "process.js"), "utf8");
        assert.ok(/shell:\s*options\.shell === true/.test(processSource), "run() must only enable a shell when the caller explicitly asks for it");
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("Validate npm spawn shape tests passed."));
