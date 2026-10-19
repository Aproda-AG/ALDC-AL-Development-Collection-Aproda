// S-3.1 (selection states, derivation, issue codes), the shared-fixture parity gate (S-2.3/S-3.4 counterpart),
// S-3.7's write rules, plus project/launch-configuration listing and the target bundle. No vscode needed.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { makeRepo, localJson, write, runTests } = require("./al-mcp-helpers");
const selection = require("../dist/alMcp/localSelection");

const fixturesRoot = path.join(__dirname, "..", "..", "..", "tests", "fixtures", "al-target");

let counter = 0;
const nextName = () => `repo-${++counter}`;

const validLaunch = `{
  // JSONC: comments and a trailing comma are valid in launch.json
  "version": "0.2.0",
  "configurations": [
    { "name": "cfg-win", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "http://nst.example.com", "serverInstance": "BC", "port": 7049, "authentication": "Windows" },
    { "name": "cfg-up", "type": "al", "request": "launch", "environmentType": "OnPrem", "server": "https://dev.example.com", "serverInstance": "BC2", "port": 7050, "authentication": "UserPassword" },
    { "name": "cfg-noauth", "type": "al", "request": "launch", "server": "http://nst.example.com", "serverInstance": "BC" },
  ]
}`;

const baseConfig = () => ({ name: "cfg", type: "al", request: "launch", environmentType: "OnPrem", server: "https://dev.example.com", serverInstance: "BC", port: 7049, authentication: "Windows" });

function selectionFor(scratch, config) {
    const repo = makeRepo(scratch, nextName(), { launch: { configurations: [config] }, local: localJson("Base", "cfg") });
    return selection.getLocalSelection(repo);
}

const tests = {
    "S-3.1 location and states: noToolkit / absent / github / root layout"(scratch) {
        const none = makeRepo(scratch, nextName(), { aldcYaml: "x: 1\n" });
        fs.rmSync(path.join(none, ".github", "aldc.yaml"));
        assert.strictEqual(selection.getLocalSelectionPath(none), null);
        assert.strictEqual(selection.getLocalSelection(none).state, "noToolkit");

        const both = makeRepo(scratch, nextName(), { launch: validLaunch });
        write(path.join(both, "aldc.yaml"), "toolkitRoot: .\n");
        assert.strictEqual(selection.getLocalSelectionPath(both), path.join(both, ".github", "aldc.local.json"), ".github wins");
        assert.strictEqual(selection.getLocalSelection(both).state, "absent");

        const root = makeRepo(scratch, nextName(), { toolkit: "root", launch: validLaunch, local: localJson("Base", "cfg-win") });
        assert.strictEqual(selection.getLocalSelectionPath(root), path.join(root, "aldc.local.json"));
        assert.strictEqual(selection.getLocalSelection(root).state, "configured");
    },

    "S-3.1 invalid matrix (same rules and reasons as S-2.2)"(scratch) {
        const cases = [
            ["file", "{ not json", "file: not strict JSON"],
            ["comment", `{\n // c\n "version": 1, "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }`, "file: not strict JSON"],
            ["comma", `{ "version": 1, "target": { "launchProject": "Base", "launchConfig": "cfg-win", } }`, "file: not strict JSON"],
            ["root", "[1]", "root:"],
            ["version 2", `{ "version": 2, "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }`, "version:"],
            ["version 1.0", `{ "version": 1.0, "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }`, "version:"],
            ["version string", `{ "version": "1", "target": { "launchProject": "Base", "launchConfig": "cfg-win" } }`, "version:"],
            ["target", `{ "version": 1, "target": "Base" }`, "target:"],
            ["launchProject missing", `{ "version": 1, "target": { "launchConfig": "cfg-win" } }`, "target.launchProject:"],
            ["launchProject empty", `{ "version": 1, "target": { "launchProject": "", "launchConfig": "cfg-win" } }`, "target.launchProject:"],
            ["launchConfig missing", `{ "version": 1, "target": { "launchProject": "Base" } }`, "target.launchConfig:"],
            ["launchConfig blank", `{ "version": 1, "target": { "launchProject": "Base", "launchConfig": " " } }`, "target.launchConfig:"],
            ["rooted drive", `{ "version": 1, "target": { "launchProject": "C:\\\\x", "launchConfig": "cfg-win" } }`, "target.launchProject: must be relative"],
            ["rooted slash", `{ "version": 1, "target": { "launchProject": "/x", "launchConfig": "cfg-win" } }`, "target.launchProject: must be relative"],
            ["dotdot leading", `{ "version": 1, "target": { "launchProject": "..\\\\Other", "launchConfig": "cfg-win" } }`, "target.launchProject: '..'"],
            ["dotdot inner", `{ "version": 1, "target": { "launchProject": "Base/../x", "launchConfig": "cfg-win" } }`, "target.launchProject: '..'"],
            ["empty file", "", "file: not strict JSON"]
        ];
        for (const [name, content, reasonPrefix] of cases) {
            const repo = makeRepo(scratch, nextName(), { launch: validLaunch, local: content });
            const result = selection.getLocalSelection(repo);
            assert.strictEqual(result.state, "invalid", `${name}: state`);
            assert.ok(result.reason && result.reason.startsWith(reasonPrefix), `${name}: reason '${result.reason}' should start with '${reasonPrefix}'`);
            assert.strictEqual(result.resolvedLaunch, null, `${name}: resolvedLaunch`);
        }
    },

    "S-3.1 stale cases and the valid selection"(scratch) {
        const noLaunch = makeRepo(scratch, nextName(), { launch: null, local: localJson("Base", "cfg-win") });
        assert.strictEqual(selection.getLocalSelection(noLaunch).state, "stale", "launch.json missing");
        const badLaunch = makeRepo(scratch, nextName(), { launch: '{ "configurations": [ ', local: localJson("Base", "cfg-win") });
        assert.strictEqual(selection.getLocalSelection(badLaunch).state, "stale", "launch.json unparseable");
        const caseDiffers = makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "CFG-WIN") });
        assert.strictEqual(selection.getLocalSelection(caseDiffers).state, "stale", "name differs in case only");
        const noServer = makeRepo(scratch, nextName(), {
            launch: '{ "configurations": [ { "name": "attach-only", "type": "al", "request": "attach" } ] }',
            local: localJson("Base", "attach-only")
        });
        assert.strictEqual(selection.getLocalSelection(noServer).state, "stale", "configuration without server");
        const otherProject = makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Missing", "cfg-win") });
        assert.strictEqual(selection.getLocalSelection(otherProject).state, "stale", "project folder without launch.json");

        const valid = makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "cfg-win") });
        const result = selection.getLocalSelection(valid);
        assert.strictEqual(result.state, "configured");
        assert.deepStrictEqual(result.target, { launchProject: "Base", launchConfig: "cfg-win" });
        assert.deepStrictEqual(result.issues, []);
    },

    "S-3.1 derivation (defaults, normalisation, JSONC launch.json)"(scratch) {
        const minimal = baseConfig();
        delete minimal.port;
        delete minimal.environmentType;
        minimal.server = "https://Host.Example.COM/";
        const resolved = selectionFor(scratch, minimal).resolvedLaunch;
        assert.strictEqual(resolved.port, 7049);
        assert.strictEqual(resolved.portSource, "default");
        assert.strictEqual(resolved.tenant, "default");
        assert.strictEqual(resolved.environmentType, "OnPrem");
        assert.strictEqual(resolved.server, "https://Host.Example.COM");
        assert.strictEqual(resolved.host, "Host.Example.COM");
        assert.strictEqual(resolved.scheme, "https");
        assert.strictEqual(resolved.credentialKey, "Host.Example.COM");
        assert.strictEqual(resolved.dependencyPublishingOption, "Default");

        const explicit = baseConfig();
        Object.assign(explicit, { port: 7100, tenant: "t9", authentication: "WINDOWS" });
        const explicitResolved = selectionFor(scratch, explicit).resolvedLaunch;
        assert.strictEqual(explicitResolved.port, 7100);
        assert.strictEqual(explicitResolved.portSource, "launch");
        assert.strictEqual(explicitResolved.tenant, "t9");
        assert.strictEqual(explicitResolved.authentication, "Windows");

        const upperScheme = baseConfig();
        upperScheme.server = "HTTPS://Up.Example.com";
        assert.strictEqual(selectionFor(scratch, upperScheme).resolvedLaunch.scheme, "https", ".NET -match is case-insensitive");

        const jsonc = makeRepo(scratch, nextName(), {
            launch: '{ /* block */ "configurations": [ { "name": "cfg", // line\n "server": "http://h", "serverInstance": "BC", "authentication": "Windows", }, ], }',
            local: localJson("Base", "cfg")
        });
        assert.strictEqual(selection.getLocalSelection(jsonc).state, "configured", "comments and trailing commas in launch.json");
    },

    "S-3.1 issue codes (same matrix as S-2.5)"(scratch) {
        const cases = [
            ["SERVER_INVALID", (c) => { c.server = "https://h.example.com/bc"; }],
            ["SERVER_INVALID", (c) => { c.server = "https://h.example.com:7049"; }],
            ["SERVER_INVALID", (c) => { c.server = "ftp://h.example.com"; }],
            ["INSTANCE_MISSING", (c) => { delete c.serverInstance; }],
            ["PORT_INVALID", (c) => { c.port = "x"; }],
            ["PORT_INVALID", (c) => { c.port = 70000; }],
            ["PORT_INVALID", (c) => { c.port = 0; }],
            ["PORT_INVALID", (c) => { c.port = 7049.5; }],
            ["NOT_ONPREM", (c) => { c.environmentType = "Sandbox"; }],
            ["AUTH_MISSING", (c) => { delete c.authentication; }],
            ["AUTH_UNSUPPORTED", (c) => { c.authentication = "AAD"; }],
            ["AUTH_UNSUPPORTED", (c) => { c.authentication = "MicrosoftEntraID"; }],
            ["AUTH_UNKNOWN", (c) => { c.authentication = "Foo"; }],
            ["USERPASSWORD_OVER_HTTP", (c) => { c.authentication = "UserPassword"; c.server = "http://h.example.com"; }],
            ["DEPENDENCY_OPTION_INVALID", (c) => { c.dependencyPublishingOption = "X"; }]
        ];
        for (const [code, change] of cases) {
            const config = baseConfig();
            change(config);
            const result = selectionFor(scratch, config);
            assert.strictEqual(result.state, "configured", `${code}: state stays configured`);
            assert.deepStrictEqual(result.issues.map((issue) => issue.code), [code], `${code}: exactly one issue`);
            assert.ok(result.issues[0].message.includes("launch.json") && result.issues[0].message.includes("'cfg'"), `${code}: message names file and configuration`);
        }
        const ignore = baseConfig();
        ignore.dependencyPublishingOption = "Ignore";
        assert.deepStrictEqual(selectionFor(scratch, ignore).issues, [], "valid dependency option");

        // Literal-level integer rule: `7049.0` is a double for ConvertFrom-Json, hence not a valid port.
        const literal = makeRepo(scratch, nextName(), {
            launch: '{ "configurations": [ { "name": "cfg", "server": "https://h.example.com", "serverInstance": "BC", "authentication": "Windows", "port": 7049.0 } ] }',
            local: localJson("Base", "cfg")
        });
        assert.deepStrictEqual(selection.getLocalSelection(literal).issues.map((issue) => issue.code), ["PORT_INVALID"]);
    },

    "S-3.1 shared fixtures parity (every tests/fixtures/al-target/case-*)"() {
        const cases = fs.readdirSync(fixturesRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory() && entry.name.startsWith("case-")).map((entry) => entry.name);
        assert.ok(cases.length >= 10, `expected at least 10 fixture cases, found ${cases.length}`);
        for (const name of cases) {
            const caseRoot = path.join(fixturesRoot, name);
            const expected = JSON.parse(fs.readFileSync(path.join(caseRoot, "expected.json"), "utf8"));
            const actual = selection.getLocalSelection(caseRoot);
            assert.strictEqual(actual.state, expected.state, `${name}: state`);
            assert.deepStrictEqual(actual.issues.map((issue) => issue.code), expected.issues, `${name}: issue codes`);
            if (expected.resolvedLaunch === null || expected.resolvedLaunch === undefined) {
                assert.strictEqual(actual.resolvedLaunch, null, `${name}: resolvedLaunch`);
            } else {
                assert.deepStrictEqual(actual.resolvedLaunch, expected.resolvedLaunch, `${name}: full resolvedLaunch (12 fields)`);
            }
            console.log(`  parity PASS ${name} (${actual.state}${actual.issues.length ? `, ${actual.issues.map((issue) => issue.code).join(",")}` : ""})`);
        }
    },

    "S-3.7 setLocalSelection: exact file, preserved keys, atomic, refusals"(scratch) {
        const repo = makeRepo(scratch, nextName(), { launch: validLaunch });
        const filePath = path.join(repo, ".github", "aldc.local.json");
        const result = selection.setLocalSelection(repo, "Base", "cfg-win");
        assert.strictEqual(result.state, "configured");
        assert.strictEqual(fs.readFileSync(filePath, "utf8"), '{\n  "version": 1,\n  "target": {\n    "launchProject": "Base",\n    "launchConfig": "cfg-win"\n  }\n}\n');
        const bytes = fs.readFileSync(filePath);
        assert.ok(!(bytes[0] === 0xef && bytes[1] === 0xbb), "no BOM");
        assert.ok(!fs.existsSync(`${filePath}.tmp`), "temporary file renamed away");

        fs.writeFileSync(filePath, '{\n  "note": { "keep": [1, 2] },\n  "version": 1,\n  "target": { "launchProject": "Base", "launchConfig": "cfg-up", "extra": true }\n}\n');
        const switched = selection.setLocalSelection(repo, "Base", "cfg-win");
        assert.strictEqual(switched.target.launchConfig, "cfg-win");
        const written = fs.readFileSync(filePath, "utf8");
        const parsed = JSON.parse(written);
        assert.deepStrictEqual(parsed.note, { keep: [1, 2] }, "unknown top-level key preserved");
        assert.strictEqual(parsed.target.extra, true, "unknown target key preserved");
        assert.strictEqual(parsed.target.launchConfig, "cfg-win");
        assert.ok(!written.includes("\r") && written.endsWith("}\n"), "LF only with trailing newline");
        assert.ok(written.includes('\n  "note": {'), "2-space indentation");

        const before = fs.readFileSync(filePath);
        assert.throws(() => selection.setLocalSelection(repo, "Base", "does-not-exist"), /^Error: SELECTION_WOULD_BE_STALE/);
        assert.throws(() => selection.setLocalSelection(repo, "..\\x", "cfg-win"), /^Error: SELECTION_WOULD_BE_INVALID/);
        assert.ok(before.equals(fs.readFileSync(filePath)), "file unchanged after refusals");
        assert.ok(!fs.existsSync(`${filePath}.tmp`), "no temporary file after refusal");

        const noToolkit = makeRepo(scratch, nextName(), { launch: validLaunch });
        fs.rmSync(path.join(noToolkit, ".github", "aldc.yaml"));
        assert.throws(() => selection.setLocalSelection(noToolkit, "Base", "cfg-win"), /^Error: SELECTION_WOULD_BE_NOTOOLKIT/);
    },

    "projects (ordinal), launch configurations and target bundle"(scratch) {
        const repo = makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "cfg-up") });
        write(path.join(repo, "Test", "app.json"), "{}");
        write(path.join(repo, "Test", ".vscode", "launch.json"), '{ "configurations": [ { "name": "t1", "server": "https://t.example.com", "serverInstance": "BC9" } ] }');
        write(path.join(repo, "x", "y", "app.json"), "{}");
        write(path.join(repo, "alpha", "app.json"), "{}");
        write(path.join(repo, "Zeta", "app.json"), "{}");
        fs.mkdirSync(path.join(repo, "Docs"));
        assert.deepStrictEqual(selection.getAlProjects(repo).map((project) => project.name), ["Base", "Test", "Zeta", "alpha"], "direct sub-folders with app.json, ordinal order");

        const configurations = selection.getLaunchConfigurations(repo);
        assert.deepStrictEqual(configurations.map((c) => `${c.launchProject}/${c.name}`), ["Base/cfg-win", "Base/cfg-up", "Base/cfg-noauth", "Test/t1"]);
        assert.strictEqual(configurations[0].authentication, "Windows");
        assert.strictEqual(configurations[2].authentication, null, "missing authentication stays null");
        assert.deepStrictEqual(configurations[2].issues.map((issue) => issue.code), ["AUTH_MISSING"]);
        assert.strictEqual(configurations[3].serverInstance, "BC9");

        const configured = selection.getLocalSelection(repo);
        assert.deepStrictEqual(selection.getTargetBundle(configured), { serverUrl: "https://dev.example.com", serverInstance: "BC2", port: 7050, authentication: "UserPassword", tenant: "default" });
        const blocked = selection.getLocalSelection(makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "cfg-noauth") }));
        assert.throws(() => selection.getTargetBundle(blocked), /^Error: TARGET_BLOCKED: AUTH_MISSING/);
        assert.throws(() => selection.getTargetBundle(null), /^Error: TARGET_NOT_CONFIGURED/);
        assert.strictEqual(selection.tryGetTargetBundle(blocked), undefined);
    },

    "local block: subset of resolvedLaunch, no credential fields, bundle only without issues"(scratch) {
        const repo = makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "cfg-up") });
        const block = selection.toLocalBlock(selection.getLocalSelection(repo));
        assert.deepStrictEqual(Object.keys(block.resolvedLaunch), [...selection.localResolvedLaunchFields]);
        assert.ok(block.targetBundle);
        const text = JSON.stringify(block);
        assert.ok(!/"(credentialKey|credential\w*|password|username|secret|token)"\s*:/i.test(text), "no credential field anywhere");

        const blockedBlock = selection.toLocalBlock(selection.getLocalSelection(makeRepo(scratch, nextName(), { launch: validLaunch, local: localJson("Base", "cfg-noauth") })));
        assert.strictEqual(blockedBlock.targetBundle, undefined);
        assert.deepStrictEqual(blockedBlock.issues.map((issue) => issue.code), ["AUTH_MISSING"]);
    }
};

runTests(tests);
