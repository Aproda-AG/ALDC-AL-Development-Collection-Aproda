const assert = require("assert");
const Module = require("module");

const vscodeMock = {};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { buildMigrationConfirmation, describeInitResult } = require("../dist/commands/initProject");
const { parseMigrationPreflight, parseAppliedCount } = require("../dist/ps/bridge");
Module._load = originalLoad;

// Both literals are READ from the PowerShell that produces them, so a reworded message breaks this
// test instead of silently breaking the feature (the language-boundary approach from bridge-dryrun-count).
const fs = require("fs");
const migrateSource = fs.readFileSync(require("path").join(__dirname, "..", "..", "aproda-sync", "Migrate-AprodaProjectLayout.ps1"), "utf8");
const syncSource = fs.readFileSync(require("path").join(__dirname, "..", "..", "aproda-sync", "Sync-AprodaLayer.ps1"), "utf8");

function testParserMatchesTheRealCurrentLine() {
    const line = /Write-Host "(Init 5: project layout already current[^"]*)"/.exec(migrateSource);
    assert.ok(line, "expected the 'already current' line in Migrate-AprodaProjectLayout.ps1");
    const preflight = parseMigrationPreflight(`${line[1]}\nInit 5: dry-run -- no files were changed.\n`);
    assert.strictEqual(preflight.status, "current");
    assert.deepStrictEqual([...preflight.actions], []);
}

function testPendingCollectsMigratedOnly() {
    const stdout = [
        "Init 5: [migrated] Removed stale root aldc.yaml (superseded by .github/aldc.yaml).",
        "Init 5: [current]  No *.code-workspace file found.",
        "Init 5: [manual]   Root aldc.yaml is still present, but .github/aldc.yaml is missing.",
        "Init 5: dry-run -- no files were changed."
    ].join("\r\n");
    const preflight = parseMigrationPreflight(stdout);
    assert.strictEqual(preflight.status, "pending");
    assert.deepStrictEqual([...preflight.actions], ["Removed stale root aldc.yaml (superseded by .github/aldc.yaml)."]);
    assert.strictEqual(preflight.manual.length, 1, "manual notes are kept for the log");
    assert.ok(!preflight.actions.some((a) => a.includes("No *.code-workspace")), "[current] must not be reported as pending work");
}

// Measured on a real pre-migration project (straub-medical-ag-base, 2026-09-29): the preflight runs
// BEFORE the pull, and every [manual] case the script can emit is either "run a pull first" -- which
// this very run does -- or "left untouched". Blocking on them would be a false alarm.
function testManualAloneDoesNotInterrupt() {
    const stdout = [
        "Init 5: [manual]   Root aldc.yaml is still present, but .github/aldc.yaml is missing -- run a pull first.",
        "Init 5: dry-run -- no files were changed."
    ].join("\r\n");
    const preflight = parseMigrationPreflight(stdout);
    assert.strictEqual(preflight.status, "current", "a manual note alone must not stop the run");
    assert.strictEqual(preflight.manual.length, 1, "but it must still be reported");
    assert.strictEqual(buildMigrationConfirmation(preflight), undefined);
}

// An unrecognised output must never read as "nothing to migrate" -- that is the B-6 class.
function testUnrecognisedOutputIsUnknown() {
    assert.strictEqual(parseMigrationPreflight("").status, "unknown");
    assert.strictEqual(parseMigrationPreflight("some unrelated output\n").status, "unknown");
}

function testConfirmationOnlyInterruptsWhenItShould() {
    assert.strictEqual(buildMigrationConfirmation({ status: "current", actions: [], manual: [] }), undefined, "a routine update must not ask");

    const pending = buildMigrationConfirmation({ status: "pending", actions: ["Removed stale root aldc.yaml."], manual: [] });
    assert.ok(pending, "a pending migration must ask");
    assert.ok(/one-way/i.test(pending.message), "the user must be told it cannot be undone");
    assert.ok(pending.message.includes("Removed stale root aldc.yaml."), "the concrete action must be named, not just counted");

    const unknown = buildMigrationConfirmation({ status: "unknown", actions: [], manual: [] });
    assert.ok(unknown, "not knowing must ask");
    assert.ok(/could not determine/i.test(unknown.message));
    assert.notStrictEqual(unknown.message, pending.message, "uncertainty must not be dressed up as a known plan");
}

function testAppliedCountMatchesTheRealDoneLine() {
    const line = /Write-Host "(Done — \$copied file\(s\) copied \+ \$dualCount dual-variant[^"]*)"/.exec(syncSource);
    assert.ok(line, "expected the 'Done —' summary in Sync-AprodaLayer.ps1");
    const rendered = line[1].replace("$copied", "135").replace("$dualCount", "2").replace("($Direction)", "(pull)");
    assert.strictEqual(parseAppliedCount(rendered), 137, `failed to read the count from: ${rendered}`);
    assert.strictEqual(parseAppliedCount("no summary here"), undefined);
}

function testResultMessage() {
    assert.ok(describeInitResult(1, "the managed toolkit cache").includes("1 file "), "singular");
    assert.ok(describeInitResult(137, "the managed toolkit cache").includes("137 files"), "plural");
    // No count parsed: never invent a zero.
    assert.ok(!/\d/.test(describeInitResult(undefined, "the local fork at C:\\x")), "an unknown count must not be reported as a number");
}

testParserMatchesTheRealCurrentLine();
testPendingCollectsMigratedOnly();
testManualAloneDoesNotInterrupt();
testUnrecognisedOutputIsUnknown();
testConfirmationOnlyInterruptsWhenItShould();
testAppliedCountMatchesTheRealDoneLine();
testResultMessage();
console.log("Migration preflight and init result tests passed.");
