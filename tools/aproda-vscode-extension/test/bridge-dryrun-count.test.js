// Item 4: the dry-run change-count extraction in bridge.ts's runBootstrap() -- the regex that parses
// PowerShell's "DRY-RUN complete — N change(s) would be applied." line back out of captured stdout.
// Both the TS regex and the PS Write-Host template are extracted VERBATIM from their real source
// files (never retyped), so a change to either side's wording is caught here instead of silently
// desyncing the two.
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const bridgeSourcePath = path.join(__dirname, "..", "src", "ps", "bridge.ts");
const syncScriptPath = path.join(__dirname, "..", "..", "aproda-sync", "Sync-AprodaLayer.ps1");

function extractBridgeRegex() {
    const source = fs.readFileSync(bridgeSourcePath, "utf8");
    const match = /const summary = (\/.*\/)\.exec\(result\.stdout\)/.exec(source);
    if (!match) {
        throw new Error("Could not extract the dry-run count regex from bridge.ts — has the code moved?");
    }
    // eslint-disable-next-line no-eval -- deliberately re-materializing the exact regex literal text
    // found in source, not hand-copied logic.
    return eval(match[1]);
}

function extractWriteHostTemplate() {
    const source = fs.readFileSync(syncScriptPath, "utf8");
    const match = /Write-Host "(DRY-RUN complete.*?)" -ForegroundColor Yellow/.exec(source);
    if (!match) {
        throw new Error("Could not extract the DRY-RUN Write-Host template from Sync-AprodaLayer.ps1 — has the code moved?");
    }
    return match[1];
}

function main() {
    const dryRunRegex = extractBridgeRegex();
    const template = extractWriteHostTemplate();
    assert.ok(template.includes("$dryRunChanges"), `template must contain the $dryRunChanges placeholder, got "${template}"`);

    const cases = [0, 1, 42];
    for (const count of cases) {
        const line = template.replace("$dryRunChanges", String(count));
        const stdout = `Some earlier PowerShell diagnostics.\n${line}\nDone.\n`;
        const match = dryRunRegex.exec(stdout);
        assert.ok(match, `expected the regex to match a real "${line}" line`);
        assert.strictEqual(Number(match[1]), count, `expected count ${count}, got "${match[1]}"`);
    }

    // Realistic full-width stdout: leading progress noise, trailing warnings, CRLF line endings (as
    // PowerShell on Windows actually emits) -- the regex has no anchors, so it must still find the
    // line wherever it sits.
    const noisyLine = template.replace("$dryRunChanges", "7");
    const noisyStdout = [
        "Resolving fork...",
        "Copying 12 file(s)...",
        "WARNING: sideInjection 'appliedRef': could not resolve source HEAD commit.",
        noisyLine,
        ""
    ].join("\r\n");
    const noisyMatch = dryRunRegex.exec(noisyStdout);
    assert.ok(noisyMatch, "expected the regex to find the DRY-RUN line inside realistic noisy CRLF stdout");
    assert.strictEqual(Number(noisyMatch[1]), 7);

    // Absence: normal (non-preview) stdout never contains this line at all -- must not match.
    const nonPreviewStdout = "Copying 12 file(s)...\nDone.\n";
    assert.strictEqual(dryRunRegex.exec(nonPreviewStdout), null, "must not match ordinary non-dry-run stdout");

    console.log("Dry-run change-count extraction tests passed.");
}

main();
