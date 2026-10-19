// S-3.4: `#aldcConfiguration` returns the `local` block, equal to the shared fixtures' expected.json
// (tests/fixtures/al-target/case-*), through the registered tool.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { createVscodeMock, withVscode, runTests, projectFolder, noCancellation } = require("./al-mcp-helpers");

const fixturesRoot = path.join(__dirname, "..", "..", "..", "tests", "fixtures", "al-target");
const localFields = ["name", "server", "serverInstance", "port", "portSource", "tenant", "environmentType", "authentication", "dependencyPublishingOption"];

async function readConfiguration(workspaceFolders) {
    const mock = createVscodeMock({ workspaceFolders });
    return withVscode(mock, async (load) => {
        const context = { subscriptions: [] };
        load("agent/readAldcConfigurationTool").registerReadAldcConfigurationTool(context);
        const tool = mock.state.registeredTools.get("aprodaAldc_readConfiguration");
        const result = await tool.invoke({ input: {} }, noCancellation);
        return JSON.parse(result.content[0].value);
    });
}

// The fixture folders sit inside the fork's own repository, so each case is copied out and gets its own .git.
// The shared aldc.yaml marker starts with a `//` comment, which is not valid YAML; the TypeScript tool parses
// aldc.yaml (the PowerShell library does not), so the copy carries a valid marker with the same meaning.
function copyFixture(scratch, name, target = name) {
    const repo = path.join(scratch, target);
    fs.cpSync(path.join(fixturesRoot, name), repo, { recursive: true });
    fs.mkdirSync(path.join(repo, ".git"));
    const marker = path.join(repo, ".github", "aldc.yaml");
    if (fs.existsSync(marker)) {
        fs.writeFileSync(marker, 'toolkitRoot: "."\n');
    }
    return repo;
}

const tests = {
    async "S-3.4 local block equals expected.json for every shared fixture case"(scratch) {
        const cases = fs.readdirSync(fixturesRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory() && entry.name.startsWith("case-")).map((entry) => entry.name);
        assert.ok(cases.length >= 10, `expected at least 10 fixture cases, found ${cases.length}`);
        for (const name of cases) {
            const expected = JSON.parse(fs.readFileSync(path.join(fixturesRoot, name, "expected.json"), "utf8"));
            // The fixture folders sit inside the fork's own repository: copy out and give the copy its own .git.
            const repo = copyFixture(scratch, name);
            fs.rmSync(path.join(repo, "expected.json"));

            const output = await readConfiguration([projectFolder(repo)]);
            if (expected.state === "noToolkit") {
                assert.strictEqual(output.state, "notInstalled", `${name}: without aldc.yaml the tool reports notInstalled`);
                assert.strictEqual(output.local, undefined, `${name}: no local block without a configured repository`);
                console.log(`  tool PASS ${name} (noToolkit -> notInstalled, no local block)`);
                continue;
            }
            assert.strictEqual(output.state, "configured", name);
            const local = output.local;
            assert.strictEqual(local.state, expected.state, `${name}: state`);
            assert.deepStrictEqual(local.issues.map((issue) => issue.code), expected.issues, `${name}: issue codes`);
            for (const issue of local.issues) {
                assert.ok(issue.message.includes("launch.json"), `${name}: ${issue.code} message`);
            }

            if (expected.resolvedLaunch === null) {
                assert.strictEqual(local.resolvedLaunch, undefined, `${name}: no resolvedLaunch`);
                assert.strictEqual(local.targetBundle, undefined, `${name}: no targetBundle`);
            } else {
                assert.deepStrictEqual(Object.keys(local.resolvedLaunch), localFields, `${name}: the documented subset`);
                for (const field of localFields) {
                    assert.strictEqual(local.resolvedLaunch[field], expected.resolvedLaunch[field], `${name}: resolvedLaunch.${field}`);
                }
                if (expected.issues.length === 0) {
                    const bundle = {
                        serverUrl: `${expected.resolvedLaunch.scheme}://${expected.resolvedLaunch.host}`,
                        serverInstance: expected.resolvedLaunch.serverInstance,
                        port: expected.resolvedLaunch.port,
                        authentication: expected.resolvedLaunch.authentication,
                        tenant: expected.resolvedLaunch.tenant
                    };
                    assert.deepStrictEqual(local.targetBundle, bundle, `${name}: targetBundle`);
                } else {
                    assert.strictEqual(local.targetBundle, undefined, `${name}: targetBundle only without blocking issues`);
                }
            }
            if (expected.state === "configured" || expected.state === "absent") {
                assert.strictEqual(local.reason, null, `${name}: reason is null`);
            } else {
                assert.ok(local.reason, `${name}: ${expected.state} carries a reason`);
            }
            assert.ok(!/"(credentialKey|password|username|secret|token)"\s*:/i.test(JSON.stringify(output)), `${name}: no credential field anywhere`);
            console.log(`  tool PASS ${name} (${local.state}${local.issues.length ? `, ${local.issues.map((issue) => issue.code).join(",")}` : ""})`);
        }
    },

    async "local block sits next to the aldc.yaml fields and extends the guidance"(scratch) {
        const repo = copyFixture(scratch, "case-configured-windows", "guidance");
        const output = await readConfiguration([projectFolder(repo)]);
        assert.strictEqual(output.toolkitRoot, ".");
        assert.strictEqual(output.local.path, path.join(repo, ".github", "aldc.local.json"));
        assert.deepStrictEqual(output.local.target, { launchProject: "Base", launchConfig: output.local.target.launchConfig });
        assert.ok(output.guidance.includes("`local` is a selection only, not an environment acknowledgement."));
        assert.ok(output.guidance.includes("Pass `targetBundle` unchanged to every `al_publish`/`al_run_tests` call."));
        assert.ok(output.guidance.includes("bcquality"), "existing guidance kept");
    }
};

runTests(tests);
