const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

class FileSystemError extends Error {
    constructor(code, arg) {
        super(typeof arg === "string" ? arg : String(arg && arg.path));
        this.code = code;
    }
    static FileNotFound(arg) { return new FileSystemError("FileNotFound", arg); }
    static FileExists(arg) { return new FileSystemError("FileExists", arg); }
    static NoPermissions(arg) { return new FileSystemError("NoPermissions", arg); }
    static Unavailable(arg) { return new FileSystemError("Unavailable", arg); }
    static FileIsADirectory(arg) { return new FileSystemError("FileIsADirectory", arg); }
}

class EventEmitter {
    constructor() { this.listeners = []; this.event = (l) => { this.listeners.push(l); return { dispose() { } }; }; }
    fire(e) { this.listeners.forEach((l) => l(e)); }
    dispose() { }
}

const Uri = {
    from: ({ scheme, authority = "", path: p = "" }) => ({ scheme, authority, path: p, fsPath: p, toString: () => `${scheme}://${authority}${p}` }),
    file: (p) => ({ scheme: "file", authority: "", path: p, fsPath: p })
};

function makeMock({ folders, settings = {}, registrations = [], warnings = [], commands = [] }) {
    return {
        Uri,
        FileSystemError,
        EventEmitter,
        Disposable: class { constructor(f) { this.dispose = f; } },
        FileType: { File: 1, Directory: 2 },
        FilePermission: { Readonly: 1 },
        FileChangeType: { Changed: 1, Created: 2, Deleted: 3 },
        workspace: {
            workspaceFolders: folders,
            workspaceFile: undefined,
            registerFileSystemProvider: (scheme, provider, options) => { registrations.push({ scheme, options }); return { dispose() { } }; },
            getConfiguration: (section) => ({ get: (key, def) => (section === "aprodaAldc" && key in settings ? settings[key] : def) })
        },
        window: {
            showWarningMessage: (message) => { warnings.push(message); return Promise.resolve(undefined); },
            showQuickPick: async () => undefined,
            showErrorMessage: () => Promise.resolve(undefined)
        },
        commands: { executeCommand: async (...args) => { commands.push(args); } }
    };
}

const modules = ["config", "env/gitRoot", "env/devRoot", "bcquality/aldcConfig", "bcquality/resolve", "bcquality/containment", "bcquality/invalidExplicit",
    "external/externalFileSystemProvider", "external/mountState", "external/doctorChecks", "commands/revealBcqualityClone", "agent/readAldcConfigurationTool"];

async function withMock(mock, fn) {
    const originalLoad = Module._load;
    Module._load = function (request, parent, isMain) {
        return request === "vscode" ? mock : originalLoad.call(this, request, parent, isMain);
    };
    for (const m of modules) { delete require.cache[require.resolve(`../dist/${m}`)]; }
    try {
        return await fn((m) => require(`../dist/${m}`));
    } finally {
        Module._load = originalLoad;
    }
}

async function makeEnv(scratch, { yaml = "external:\n  bcquality:\n    enabled: true\n", withExternal = true } = {}) {
    const repo = path.join(scratch, "repo");
    const clone = path.join(scratch, "clone");
    await fs.mkdir(path.join(repo, ".git"), { recursive: true });
    await fs.writeFile(path.join(repo, "aldc.yaml"), yaml);
    await fs.mkdir(path.join(clone, "skills"), { recursive: true });
    await fs.writeFile(path.join(clone, "skills", "entry.md"), "# entry");
    await fs.writeFile(path.join(clone, "skills", "read.md"), "read");
    if (withExternal) {
        await fs.mkdir(path.join(repo, ".external"), { recursive: true });
        await fs.writeFile(path.join(repo, ".external", "README.md"), "readme");
    }
    return { repo, clone };
}

const codeOf = async (promise) => { try { await promise; return "ok"; } catch (e) { return e.code; } };
const u = (p, authority = "") => Uri.from({ scheme: "aldc-external", authority, path: p });
const text = (bytes) => Buffer.from(bytes).toString("utf8");
const names = (entries) => entries.map(([n]) => n).sort();

async function testProvider(scratch) {
    const { repo, clone } = await makeEnv(scratch);
    const registrations = [];
    const mock = makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone, "bcquality.autoReconcile": false }, registrations });
    await withMock(mock, async (req) => {
        const mod = req("external/externalFileSystemProvider");
        const logs = [];
        const provider = mod.registerExternalFileSystemProvider({ subscriptions: [] }, { info: (m) => logs.push(m) });
        // S-11.1
        assert.deepStrictEqual(registrations, [{ scheme: "aldc-external", options: { isCaseSensitive: false } }]);
        // S-11.2 virtual
        assert.deepStrictEqual(names(await provider.readDirectory(u("/"))), ["README.md", "bcquality"]);
        // S-11.3 / S-11.4
        assert.strictEqual(text(await provider.readFile(u("/bcquality/skills/read.md"))), "read");
        assert.strictEqual(text(await provider.readFile(u("///bcquality/skills/read.md"))), "read");
        assert.strictEqual(text(await provider.readFile(u("/skills/read.md", "bcquality"))), "read");
        assert.strictEqual(text(await provider.readFile(u("/README.md"))), "readme");
        // S-11.5
        assert.strictEqual(await codeOf(provider.readFile(u("/bcquality/../../x"))), "FileNotFound");
        assert.strictEqual(await codeOf(provider.readFile(u("/../README.md"))), "FileNotFound");
        assert.deepStrictEqual(names(await provider.readDirectory(u("/bcquality/skills/.."))), ["skills"]);
        // S-11.6 writes act on the real files; root and source roots are protected
        const write = (p, s, o = { create: true, overwrite: true }) => provider.writeFile(u(p), Buffer.from(s), o);
        const disk = (...p) => fs.readFile(path.join(...p), "utf8");
        await write("/README.md", "edited");
        assert.strictEqual(await disk(repo, ".external", "README.md"), "edited");
        await write("/bcquality/skills/read.md", "clone-edited");
        assert.strictEqual(await disk(clone, "skills", "read.md"), "clone-edited");
        await write("/bcquality/skills/new.md", "new");
        assert.strictEqual(await disk(clone, "skills", "new.md"), "new");
        assert.strictEqual(await codeOf(write("/bcquality/skills/new.md", "x", { create: true, overwrite: false })), "FileExists");
        assert.strictEqual(await codeOf(write("/bcquality/skills/absent.md", "x", { create: false, overwrite: true })), "FileNotFound");
        assert.strictEqual(await codeOf(write("/bcquality/nodir/x.md", "x")), "FileNotFound");
        await provider.createDirectory(u("/notes"));
        await write("/notes/a.md", "a");
        await provider.rename(u("/notes/a.md"), u("/notes/b.md"), { overwrite: false });
        assert.strictEqual(await disk(repo, ".external", "notes", "b.md"), "a");
        await provider.delete(u("/notes"), { recursive: true });
        assert.strictEqual(await codeOf(fs.stat(path.join(repo, ".external", "notes"))), "ENOENT");
        await provider.delete(u("/bcquality/skills/new.md"), { recursive: false });
        assert.strictEqual(await codeOf(fs.stat(path.join(clone, "skills", "new.md"))), "ENOENT");
        for (const p of ["/", "/bcquality", "/BCQuality"]) {
            assert.strictEqual(await codeOf(provider.delete(u(p), { recursive: true })), "NoPermissions", p);
            assert.strictEqual(await codeOf(provider.rename(u(p), u("/moved"), { overwrite: false })), "NoPermissions", p);
        }
        assert.strictEqual(await codeOf(provider.createDirectory(u("/bcquality"))), "NoPermissions");
        assert.strictEqual(await codeOf(write("/bcquality/../../x.md", "x")), "FileNotFound");
        assert.ok(await fs.stat(path.join(clone, "skills", "entry.md")));
        // S-11.10
        const events = [];
        provider.onDidChangeFile((e) => events.push(e));
        provider.refresh();
        assert.strictEqual(events.length, 1);
        assert.deepStrictEqual(events[0].map((e) => e.uri.path), ["/", "/bcquality"]);
        // resolveToDisk (reveal)
        assert.strictEqual(path.resolve(await provider.resolveToDisk(u("/README.md"))), path.resolve(repo, ".external", "README.md"));
        assert.strictEqual(path.resolve(await provider.resolveToDisk(u("/bcquality/skills/read.md"))), path.resolve(clone, "skills", "read.md"));
    });
}

async function testMountNoneAndDisabledAndSymlink(scratch) {
    const { repo, clone } = await makeEnv(scratch);
    // S-11.2 none
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone, "external.mount": "none" } }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        assert.deepStrictEqual(names(await provider.readDirectory(u("/"))), ["README.md"]);
    });
    // S-11.8
    await fs.writeFile(path.join(repo, "aldc.yaml"), "external:\n  bcquality:\n    enabled: false\n");
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone } }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        assert.deepStrictEqual(names(await provider.readDirectory(u("/"))), ["README.md"]);
        assert.strictEqual(await codeOf(provider.readFile(u("/bcquality/skills/read.md"))), "FileNotFound");
    });
    // S-11.5 symlink escape (skipped where symlinks are not permitted)
    await fs.writeFile(path.join(repo, "aldc.yaml"), "external:\n  bcquality:\n    enabled: true\n");
    const outside = path.join(scratch, "outside");
    await fs.mkdir(outside, { recursive: true });
    await fs.writeFile(path.join(outside, "secret.txt"), "secret");
    let linked = true;
    try { await fs.symlink(outside, path.join(clone, "link"), "junction"); } catch { linked = false; }
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone } }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        if (linked) {
            assert.strictEqual(await codeOf(provider.readFile(u("/bcquality/link/secret.txt"))), "FileNotFound");
            // a new file below a link inside the clone must not land outside
            assert.strictEqual(await codeOf(provider.writeFile(u("/bcquality/link/planted.txt"), Buffer.from("x"), { create: true, overwrite: true })), "FileNotFound");
            assert.strictEqual(await codeOf(fs.stat(path.join(outside, "planted.txt"))), "ENOENT");
        }
        if (process.platform === "win32") {
            assert.strictEqual(await codeOf(provider.readFile(u("/bcquality/skills/read.md::$DATA"))), "FileNotFound");
        }
    });
}

async function testUnresolvedAndNoRepo(scratch) {
    const { repo } = await makeEnv(scratch);
    // S-11.7
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": path.join(scratch, "missing") } }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        let message = "";
        try { await provider.readFile(u("/bcquality/skills/read.md")); } catch (e) { assert.strictEqual(e.code, "Unavailable"); message = e.message; }
        assert.ok(message.includes("Tried:") && message.includes("setting=") && message.includes("["), "msg=" + message);
    });
    // S-11.9
    await withMock(makeMock({ folders: [{ uri: Uri.file(path.join(scratch, "nowhere")) }] }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        let message = "";
        try { await provider.stat(u("/")); } catch (e) { assert.strictEqual(e.code, "Unavailable"); message = e.message; }
        assert.ok(message.includes("No ALDC repository"));
    });
}

async function testUnknownSourceAndVirtualFolder(scratch) {
    const { repo, clone } = await makeEnv(scratch, { yaml: "external:\n  bcquality:\n    enabled: true\n  other:\n    enabled: true\n" });
    const folders = [{ uri: { scheme: "aldc-external", path: "/", fsPath: "/" } }, { uri: Uri.file(repo) }];
    await withMock(makeMock({ folders, settings: { "bcquality.path": clone } }), async (req) => {
        const logs = [];
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)({ info: (m) => logs.push(m) });
        await provider.readDirectory(u("/"));
        await provider.readDirectory(u("/"));
        assert.strictEqual(logs.filter((l) => l.includes("external.other")).length, 1); // S-11.11
        // S-11.12
        const resolution = await req("bcquality/resolve").resolveBcquality();
        assert.ok(!resolution.candidates.some((c) => c.path === "/" || c.path === path.resolve("/")));
    });
}

async function testInvalidExplicit(scratch) {
    const { repo, clone } = await makeEnv(scratch);
    const bad = path.join(scratch, "bad");
    await fs.mkdir(bad, { recursive: true });
    const warnings = [];
    const mock = makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { devRoot: scratch, "bcquality.path": bad }, warnings });
    // devRoot/BCQuality-Aproda serves BCQuality
    await fs.mkdir(path.join(scratch, "BCQuality-Aproda", "skills"), { recursive: true });
    await fs.writeFile(path.join(scratch, "BCQuality-Aproda", "skills", "entry.md"), "x");
    const saved = process.env.BCQUALITY_HOME;
    delete process.env.BCQUALITY_HOME;
    try {
        await withMock(mock, async (req) => {
            const logger = { warn: (m) => warnings.push("log:" + m) };
            await req("bcquality/invalidExplicit").warnInvalidExplicitCandidates(logger);
            await req("bcquality/invalidExplicit").warnInvalidExplicitCandidates(logger);
            await new Promise((r) => setImmediate(r));
            assert.strictEqual(warnings.filter((w) => !w.startsWith("log:")).length, 1); // S-11.13
            assert.ok(warnings[0].includes("aprodaAldc.bcquality.path") || warnings[1].includes("aprodaAldc.bcquality.path"));
            // D-4: a memento carries the dedupe across activations; a changed value warns again.
            const store = new Map();
            const memento = { get: (k) => store.get(k), update: async (k, v) => { store.set(k, v); } };
            const before = warnings.length;
            const mod = req("bcquality/invalidExplicit");
            const resolution = await req("bcquality/resolve").resolveBcquality();
            const other = { ...resolution, candidates: resolution.candidates.map((c) => (c.source === "setting" ? { ...c, path: c.path + "-x" } : c)) };
            await mod.warnInvalidExplicitCandidates(logger, other, memento);
            await mod.warnInvalidExplicitCandidates(logger, other, memento);
            await new Promise((r) => setImmediate(r));
            assert.strictEqual(warnings.length - before, 2, "one log + one toast, then nothing on re-activation");
            const changed = { ...resolution, candidates: resolution.candidates.map((c) => (c.source === "setting" ? { ...c, path: c.path + "-y" } : c)) };
            await mod.warnInvalidExplicitCandidates(logger, changed, memento);
            await new Promise((r) => setImmediate(r));
            assert.strictEqual(warnings.length - before, 4, "changed value warns again");
        });
        // S-11.14: devRoot/aldcYaml alone never warn
        const none = [];
        await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { devRoot: scratch }, warnings: none }), async (req) => {
            await req("bcquality/invalidExplicit").warnInvalidExplicitCandidates({ warn: (m) => none.push(m) });
            assert.strictEqual(none.length, 0);
        });
        // environment
        process.env.BCQUALITY_HOME = bad;
        const env = [];
        await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { devRoot: scratch }, warnings: env }), async (req) => {
            await req("bcquality/invalidExplicit").warnInvalidExplicitCandidates({ warn: (m) => env.push(m) });
            await new Promise((r) => setImmediate(r));
            assert.ok(env.some((m) => m.includes("BCQUALITY_HOME")));
        });
    } finally {
        if (saved === undefined) { delete process.env.BCQUALITY_HOME; } else { process.env.BCQUALITY_HOME = saved; }
    }
    void clone;
}

async function testConfigurationTool(scratch) {
    const { repo, clone } = await makeEnv(scratch);
    for (const mount of ["virtual", "none"]) {
        await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone, "external.mount": mount } }), async (req) => {
            const registered = [];
            const vscode = require("vscode");
            vscode.lm = { registerTool: (name, tool) => { registered.push(tool); return { dispose() { } }; } };
            vscode.LanguageModelToolResult = class { constructor(parts) { this.parts = parts; } };
            vscode.LanguageModelTextPart = class { constructor(value) { this.value = value; } };
            req("agent/readAldcConfigurationTool").registerReadAldcConfigurationTool({ subscriptions: [] });
            const result = await registered[0].invoke({}, {});
            const json = JSON.parse(result.parts[0].value);
            assert.strictEqual(json.bcquality.mount, mount); // S-11.25
            assert.strictEqual(json.bcquality.mountUri, mount === "virtual" ? "aldc-external:/bcquality/" : undefined);
            assert.strictEqual(json.bcquality.diskPath, undefined);
            assert.ok(json.guidance.includes("#bcquality") && json.guidance.includes("mountUri") && json.guidance.includes("external.bcquality.fallback"));
        });
    }
}

async function testRevealAndDoctor(scratch) {
    const { repo, clone } = await makeEnv(scratch);
    const commands = [];
    const warnings = [];
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": clone }, commands, warnings }), async (req) => {
        const mod = req("external/externalFileSystemProvider");
        const provider = new mod.ExternalFileSystemProvider();
        const reveal = req("commands/revealBcqualityClone").revealBcqualityClone;
        const spawned = [];
        const spawner = (command, args, options) => spawned.push({ command, args, options });
        const target = (i) => spawned[i].args.join(" ");
        await reveal(provider, undefined, spawner);
        assert.ok(target(0).includes(path.join(clone, "skills", "entry.md"))); // S-11.26
        await reveal(provider, u("/bcquality/skills/read.md"), spawner);
        assert.ok(target(1).includes(path.join(clone, "skills", "read.md")));
        await reveal(provider, u("/README.md"), spawner);
        assert.ok(target(2).includes(path.join(repo, ".external", "README.md")));
        assert.strictEqual(commands.length, 0); // no revealFileInOS
        // D-3: paths with spaces and umlauts, per platform
        const build = req("commands/revealBcqualityClone").buildRevealCommand;
        const odd = "C:\\Florian Köll\\a b\\entry.md";
        const win = build(odd, "win32");
        assert.deepStrictEqual([win.command, win.args, win.options.windowsVerbatimArguments], ["explorer.exe", [`/select,"${odd}"`], true]);
        assert.deepStrictEqual(build("/a b/ä.md", "darwin").args, ["-R", "/a b/ä.md"]);
        assert.deepStrictEqual(build("/a b/ä.md", "linux").args, ["/a b"]);
        // nonexistent path: warning, no spawn
        await reveal(provider, u("/bcquality/skills/missing.md"), spawner);
        assert.strictEqual(spawned.length, 3);
        // S-11.27 doctor
        const { buildExternalFindings } = req("external/doctorChecks");
        const base = { rootForm: "uri", autoReconcile: true, mount: "virtual", junction: "absent" };
        assert.deepStrictEqual(buildExternalFindings(base), []);
        assert.strictEqual(buildExternalFindings({ ...base, rootForm: "path", autoReconcile: false }).length, 1);
        assert.strictEqual(buildExternalFindings({ ...base, junction: "readable", junctionPath: "X" }).length, 1);
        const unreadable = buildExternalFindings({ ...base, junction: "unreadable", junctionPath: "X" });
        assert.ok(unreadable.some((f) => f.message.includes("rmdir")));
    });
    const commands2 = [];
    const warnings2 = [];
    await withMock(makeMock({ folders: [{ uri: Uri.file(repo) }], settings: { "bcquality.path": path.join(scratch, "missing") }, commands: commands2, warnings: warnings2 }), async (req) => {
        const provider = new (req("external/externalFileSystemProvider").ExternalFileSystemProvider)();
        await req("commands/revealBcqualityClone").revealBcqualityClone(provider);
        assert.strictEqual(commands2.length, 0);
        assert.ok(warnings2[0].includes("Tried:"));
    });
}

async function testManifest() {
    const pkg = require("../package.json");
    const setting = pkg.contributes.configuration.properties["aprodaAldc.external.mount"];
    assert.deepStrictEqual(setting.enum, ["virtual", "junction", "none"]);
    assert.strictEqual(setting.default, "virtual");
    assert.strictEqual(setting.scope, "application");
    assert.ok(pkg.contributes.commands.some((c) => c.command === "aprodaAldc.revealBcqualityClone"));
    assert.ok(pkg.contributes.menus["explorer/context"].some((m) => m.command === "aprodaAldc.revealExternalPath" && m.when === "resourceScheme == aldc-external"));
    const config = require("../dist/config");
    void config;
}

(async () => {
    delete process.env.BCQUALITY_HOME;
    const tests = [testProvider, testMountNoneAndDisabledAndSymlink, testUnresolvedAndNoRepo, testUnknownSourceAndVirtualFolder,
        testInvalidExplicit, testConfigurationTool, testRevealAndDoctor];
    for (const test of tests) {
        const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aldc-ext-"));
        try {
            await test(scratch);
            console.log(`ok - ${test.name}`);
        } finally {
            await fs.rm(scratch, { recursive: true, force: true }).catch(() => undefined);
        }
    }
    await testManifest();
    console.log("ok - testManifest");
})().catch((error) => { console.error(error); process.exit(1); });
