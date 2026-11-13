const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const messages = [];
const warnings = [];
let workspaceFile;
const vscodeMock = {
    workspace: { get workspaceFile() { return workspaceFile; } },
    window: { showWarningMessage: (message) => { warnings.push(message); } },
    Uri: { file: (fsPath) => ({ scheme: "file", fsPath }) }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { migrateWorkspaceText, migrateWorkspaceFile } = require("../dist/external/workspaceMigration");

const logger = { info: (m) => messages.push(m), warn: (m) => messages.push(`WARN: ${m}`), error: (m) => messages.push(`ERROR: ${m}`) };
const constant = '"uri": "aldc-external:/"';

function folderPaths(text) {
    const { parse } = require("jsonc-parser");
    return parse(text).folders;
}

async function testPathRootReplacedByteIdentical() {
    // S-11.15
    const before = '{\n  // keep me\n  "folders": [\n    { "path": "." }, // project\n    { "name": ".external", "path": ".external" }\n  ],\n  /* settings */\n  "settings": { "a": 1 }\n}\n';
    const result = await migrateWorkspaceText(before, os.tmpdir());
    const expected = before.replace('{ "name": ".external", "path": ".external" }', '{ "name": ".external", "uri": "aldc-external:/" }');
    assert.strictEqual(result.text, expected);
}

async function testSecondRunNoWrite() {
    // S-11.16, S-11.17, S-11.19 (file level)
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "aldc-mig-"));
    try {
        const file = path.join(dir, "p.code-workspace");
        await fs.writeFile(file, '{\n  "folders": [\n    { "path": "." }\n  ]\n}\n');
        workspaceFile = { scheme: "file", fsPath: file };
        assert.strictEqual(await migrateWorkspaceFile(dir, logger), true);
        const text = await fs.readFile(file, "utf8");
        assert.deepStrictEqual(folderPaths(text), [{ path: "." }, { name: ".external", uri: "aldc-external:/" }]);
        assert.ok(!text.startsWith("\uFEFF"));
        const old = new Date(Date.now() - 60000);
        await fs.utimes(file, old, old);
        const mtime = (await fs.stat(file)).mtimeMs;
        assert.strictEqual(await migrateWorkspaceFile(dir, logger), false);
        assert.strictEqual((await fs.stat(file)).mtimeMs, mtime);
        assert.strictEqual(await fs.readFile(file, "utf8"), text);
    } finally {
        await fs.rm(dir, { recursive: true, force: true });
    }
}

async function testUnparseable() {
    // S-11.18
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "aldc-mig-"));
    try {
        const file = path.join(dir, "p.code-workspace");
        const broken = '{ "folders": [ { "path": ". } ';
        await fs.writeFile(file, broken);
        workspaceFile = { scheme: "file", fsPath: file };
        warnings.length = 0;
        messages.length = 0;
        assert.strictEqual(await migrateWorkspaceFile(dir, logger), false);
        assert.strictEqual(await fs.readFile(file, "utf8"), broken);
        assert.ok(messages.some((m) => m.startsWith("WARN:") && m.includes("Manually add")));
        assert.strictEqual(warnings.length, 1);
    } finally {
        await fs.rm(dir, { recursive: true, force: true });
    }
}

const legacyForms = ["../BCQuality-Aproda", "../../BCQuality-Aproda", "C:\\\\dev\\\\BCQuality-Aproda", "../bcquality-aproda", "../bcquality"];

function legacyWorkspace(legacy) {
    return `{
  // header comment
  "folders": [
    { "path": "." },
    { "path": "${legacy}" } // legacy clone
  ],
  "settings": {
    "search.exclude": { "**/node_modules": true, "${legacy}/**": true },
    "files.watcherExclude": { "${legacy}/**": true, "**/.git/**": true },
    "terminal.integrated.env.windows": { "BCQUALITY_HOME": "C:\\\\x" },
    "terminal.integrated.env.linux": { "BCQUALITY_HOME": "/x", "OTHER": "1" }
  }
}
`;
}

async function testLegacyForms() {
    // S-11.18a
    for (const legacy of legacyForms) {
        const result = await migrateWorkspaceText(legacyWorkspace(legacy), os.tmpdir());
        const { parse } = require("jsonc-parser");
        const data = parse(result.text);
        assert.deepStrictEqual(data.folders, [{ path: "." }, { name: ".external", uri: "aldc-external:/" }], legacy);
        assert.deepStrictEqual(data.settings["search.exclude"], { "**/node_modules": true }, legacy);
        assert.deepStrictEqual(data.settings["files.watcherExclude"], { "**/.git/**": true }, legacy);
        assert.ok(!("terminal.integrated.env.windows" in data.settings), legacy);
        assert.deepStrictEqual(data.settings["terminal.integrated.env.linux"], { OTHER: "1" }, legacy);
        assert.ok(result.text.includes("// header comment"), legacy);
        assert.strictEqual(result.text.split(constant).length - 1, 1, legacy);
    }
    // folder with another name that contains skills/entry.md
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "aldc-mig-"));
    try {
        await fs.mkdir(path.join(dir, "ws", "kb", "skills"), { recursive: true });
        await fs.writeFile(path.join(dir, "ws", "kb", "skills", "entry.md"), "#");
        const result = await migrateWorkspaceText('{ "folders": [ { "path": "." }, { "path": "kb" } ] }', path.join(dir, "ws"));
        assert.deepStrictEqual(folderPaths(result.text), [{ path: "." }, { name: ".external", uri: "aldc-external:/" }]);
    } finally {
        await fs.rm(dir, { recursive: true, force: true });
    }
}

async function testLegacyPlusExternal() {
    // S-11.18b
    const text = '{ "folders": [ { "path": "." }, { "path": "../BCQuality-Aproda" }, { "name": ".external", "path": ".external" } ] }';
    const result = await migrateWorkspaceText(text, os.tmpdir());
    assert.deepStrictEqual(folderPaths(result.text), [{ path: "." }, { name: ".external", uri: "aldc-external:/" }]);
}

async function testCopiesIdentical() {
    // S-11.18c
    const make = (legacy) => `{\n  "folders": [\n    { "path": "." },\n    { "path": "${legacy}" }\n  ]\n}\n`;
    const a = await migrateWorkspaceText(make("../BCQuality-Aproda"), os.tmpdir());
    const b = await migrateWorkspaceText(make("../../BCQuality-Aproda"), os.tmpdir());
    assert.strictEqual(a.text, b.text);
}

async function testUnrelatedBcqualityNameUntouched() {
    // S-11.18d
    const text = '{ "folders": [ { "path": "." }, { "path": "my-bcquality-notes" } ] }';
    const result = await migrateWorkspaceText(text, os.tmpdir());
    const folders = folderPaths(result.text);
    assert.deepStrictEqual(folders, [{ path: "." }, { path: "my-bcquality-notes" }, { name: ".external", uri: "aldc-external:/" }]);
}

async function testNoWorkspaceOrOutside() {
    // S-11.19
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "aldc-mig-"));
    try {
        const repo = path.join(dir, "repo");
        await fs.mkdir(repo);
        const outside = path.join(dir, "other.code-workspace");
        const original = '{ "folders": [ { "path": "." } ] }';
        await fs.writeFile(outside, original);
        workspaceFile = undefined;
        messages.length = 0;
        assert.strictEqual(await migrateWorkspaceFile(repo, logger), false);
        assert.ok(messages.some((m) => m.includes("aldc-external:/")));
        workspaceFile = { scheme: "file", fsPath: outside };
        messages.length = 0;
        assert.strictEqual(await migrateWorkspaceFile(repo, logger), false);
        assert.strictEqual(await fs.readFile(outside, "utf8"), original);
        assert.ok(messages.some((m) => m.includes("outside the repository")));
    } finally {
        await fs.rm(dir, { recursive: true, force: true });
    }
}

async function main() {
    try {
        await testPathRootReplacedByteIdentical();
        await testSecondRunNoWrite();
        await testUnparseable();
        await testLegacyForms();
        await testLegacyPlusExternal();
        await testCopiesIdentical();
        await testUnrelatedBcqualityNameUntouched();
        await testNoWorkspaceOrOutside();
        console.log("external workspace migration tests passed.");
    } finally {
        Module._load = originalLoad;
    }
}

main();
