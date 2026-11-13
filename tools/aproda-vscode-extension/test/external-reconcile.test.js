const assert = require("assert");
const fsp = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const settings = {};
let workspaceFile;
const updates = [];
const warnings = [];
const vscodeMock = {
    workspace: {
        workspaceFolders: [],
        get workspaceFile() { return workspaceFile; },
        getConfiguration: () => ({
            get: (key, defaultValue) => (key in settings ? settings[key] : defaultValue),
            inspect: (key) => (key in settings ? { globalValue: settings[key] } : undefined),
            update: async (key, value) => { updates.push([key, value]); }
        })
    },
    window: { showWarningMessage: () => undefined },
    ConfigurationTarget: { Global: 1 },
    Uri: { file: (fsPath) => ({ scheme: "file", fsPath }) }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { reconcileBcquality } = require("../dist/workspace/bcqualityRoot");

function makeLogger() {
    const lines = [];
    return { lines, info: (m) => lines.push(m), warn: (m) => { lines.push(`WARN: ${m}`); warnings.push(m); }, error: (m) => lines.push(`ERROR: ${m}`) };
}

async function setup(scratch, label, { disabled = false } = {}) {
    const repo = path.join(scratch, `repo-${label}`);
    await fsp.mkdir(path.join(repo, ".git"), { recursive: true });
    if (disabled) {
        await fsp.writeFile(path.join(repo, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");
    }
    const clone = path.join(scratch, `clone-${label}`);
    await fsp.mkdir(path.join(clone, "skills"), { recursive: true });
    await fsp.writeFile(path.join(clone, "skills", "entry.md"), "#");
    const file = path.join(repo, "p.code-workspace");
    await fsp.writeFile(file, '{\n  "folders": [\n    { "path": "." },\n    { "path": "../BCQuality-Aproda" }\n  ]\n}\n');
    workspaceFile = { scheme: "file", fsPath: file };
    process.env.BCQUALITY_HOME = clone;
    vscodeMock.workspace.workspaceFolders = [{ uri: { fsPath: repo } }];
    return { repo, clone, file, link: path.join(repo, ".external", "bcquality") };
}

async function exists(p) {
    return fsp.lstat(p).then(() => true, () => false);
}

function reset(overrides = {}) {
    for (const key of Object.keys(settings)) {
        delete settings[key];
    }
    Object.assign(settings, overrides);
    updates.length = 0;
    warnings.length = 0;
}

async function main() {
    const scratch = await fsp.mkdtemp(path.join(os.tmpdir(), "aldc-reconcile-"));
    delete process.env.BCQUALITY_HOME;
    try {
        // S-11.21: junction mount creates a link, virtual/none remove it (target untouched).
        let t = await setup(scratch, "a");
        reset({ "external.mount": "junction" });
        const logger = makeLogger();
        let hook = 0;
        await reconcileBcquality(t.repo, t.clone, logger, () => { hook++; });
        assert.ok((await fsp.lstat(t.link)).isSymbolicLink(), "junction mount must create link");
        assert.strictEqual(hook, 1, "onReconciled runs once per reconcile (S-11.24 hook)");
        assert.ok((await fsp.readFile(t.file, "utf8")).includes("aldc-external:/"), "migration runs for junction too");
        for (const mount of ["virtual", "none"]) {
            if (!(await exists(t.link))) {
                await require("../dist/workspace/bcqualityRoot").createBcqualityLink(t.link, t.clone, logger);
            }
            reset({ "external.mount": mount });
            await reconcileBcquality(t.repo, t.clone, logger);
            assert.ok(!(await exists(t.link)), `${mount} must remove link`);
            assert.ok(await exists(path.join(t.clone, "skills", "entry.md")), "link target untouched");
        }

        // S-11.20: autoReconcile=false touches nothing.
        t = await setup(scratch, "b");
        reset({ "external.mount": "junction", "bcquality.autoReconcile": false });
        const before = await fsp.readFile(t.file, "utf8");
        await reconcileBcquality(t.repo, t.clone, makeLogger());
        assert.strictEqual(await fsp.readFile(t.file, "utf8"), before);
        assert.ok(!(await exists(t.link)));
        assert.strictEqual(updates.length, 0);

        // S-11.23: enabled:false with autoReconcile=false still removes the link.
        t = await setup(scratch, "c", { disabled: true });
        reset({ "external.mount": "junction", "bcquality.autoReconcile": false });
        await require("../dist/workspace/bcqualityRoot").createBcqualityLink(t.link, t.clone, makeLogger());
        assert.ok(await exists(t.link));
        await reconcileBcquality(t.repo, t.clone, makeLogger());
        assert.ok(!(await exists(t.link)), "kill-switch removes link");

        // Empty-home guard: nothing resolvable -> no BCQUALITY_HOME write.
        t = await setup(scratch, "d");
        reset({ "external.mount": "virtual" });
        await reconcileBcquality(t.repo, "", makeLogger());
        assert.ok(!updates.some(([key, value]) => key === "terminal.integrated.env.windows" && !value));

        // S-11.22: link removal fails -> warning with rmdir hint, no throw.
        t = await setup(scratch, "e");
        reset({ "external.mount": "junction" });
        await require("../dist/workspace/bcqualityRoot").createBcqualityLink(t.link, t.clone, makeLogger());
        const realRmdir = fsp.rmdir;
        const realUnlink = fsp.unlink;
        fsp.rmdir = async () => { throw Object.assign(new Error("EPERM"), { code: "EPERM" }); };
        fsp.unlink = async () => { throw Object.assign(new Error("EPERM"), { code: "EPERM" }); };
        const failLogger = makeLogger();
        reset({ "external.mount": "none" });
        try {
            await reconcileBcquality(t.repo, t.clone, failLogger);
        } finally {
            fsp.rmdir = realRmdir;
            fsp.unlink = realUnlink;
        }
        assert.ok(failLogger.lines.some((l) => l.startsWith("WARN:") && l.includes("cmd /c rmdir")), failLogger.lines.join("\n"));
        console.log("external reconcile tests passed.");
    } finally {
        Module._load = originalLoad;
        await fsp.rm(scratch, { recursive: true, force: true });
    }
}

main().catch((error) => { console.error(error); process.exit(1); });
