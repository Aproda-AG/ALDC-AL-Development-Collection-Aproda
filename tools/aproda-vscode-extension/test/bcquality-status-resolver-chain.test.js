// Item 5: the resolver-chain QuickPick construction in bcqualityStatus.ts (buildResolverChainItems),
// specifically the workspaceFolder-rung collapsing rule -- a normal multi-root project produces one
// "verified" workspaceFolder candidate plus several unsuccessful ones, and only that winner (or, if
// none won, a single collapsed summary line) should ever reach the QuickPick, never a wall of
// individual unsuccessful "Mounted workspace folder" lines.
//
// `buildResolverChainItems` was previously a module-private function; the minimal, explicitly-flagged
// second source change for this task adds an `export` keyword to it so it is directly testable here
// with real BcqualityResolution/BcqualityCandidate objects, instead of only reachable through the full
// interactive showBcqualityStatus() QuickPick flow.
const assert = require("assert");
const Module = require("module");

const vscodeMock = {
    QuickPickItemKind: { Separator: -1 }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { buildResolverChainItems } = require("../dist/commands/bcqualityStatus");
Module._load = originalLoad;

function candidate(source, verdict, extra = {}) {
    return { source, verdict, ...extra };
}

function resolution(candidates) {
    return { verified: false, enabled: "auto", entryPoint: "skills/entry.md", candidates };
}

function main() {
    // Non-workspaceFolder candidates pass through one-to-one, in order.
    const simple = resolution([
        candidate("setting", "notSet"),
        candidate("environment", "verified", { path: "/env/bcquality", realPath: undefined })
    ]);
    const simpleItems = buildResolverChainItems(simple);
    assert.strictEqual(simpleItems.length, 2);
    assert.ok(simpleItems[0].label.includes("VS Code setting"));
    assert.ok(simpleItems[1].label.includes("$BCQUALITY_HOME"));

    // Multiple workspaceFolder candidates, none verified: collapsed into exactly one summary line,
    // with the correct probed count and no per-folder detail leaking through.
    const noneVerified = resolution([
        candidate("setting", "notSet"),
        candidate("workspaceFolder", "missing", { path: "/ws/a" }),
        candidate("workspaceFolder", "noEntryPoint", { path: "/ws/b" }),
        candidate("workspaceFolder", "missing", { path: "/ws/c" }),
        candidate("devRoot", "notSet")
    ]);
    const noneVerifiedItems = buildResolverChainItems(noneVerified);
    assert.strictEqual(noneVerifiedItems.length, 3, `expected setting + 1 collapsed workspaceFolder line + devRoot, got ${noneVerifiedItems.length}`);
    assert.ok(noneVerifiedItems[1].label.includes("Mounted workspace folder"));
    assert.ok(noneVerifiedItems[1].description.includes("3 probed"));
    assert.ok(noneVerifiedItems[1].description.includes(noneVerified.entryPoint));

    // Multiple workspaceFolder candidates, one verified: the winner is shown explicitly (its own
    // detail line, not collapsed away), and the remaining unsuccessful ones are collapsed into a
    // single summary line counting only the LOSERS (not the winner itself).
    const oneVerified = resolution([
        candidate("workspaceFolder", "missing", { path: "/ws/a" }),
        candidate("workspaceFolder", "verified", { path: "/ws/b", realPath: "/ws/b-real" }),
        candidate("workspaceFolder", "noEntryPoint", { path: "/ws/c" }),
        candidate("aldcYaml", "notSet")
    ]);
    const oneVerifiedItems = buildResolverChainItems(oneVerified);
    assert.strictEqual(oneVerifiedItems.length, 3, `expected winner + 1 collapsed line + aldcYaml, got ${oneVerifiedItems.length}`);
    assert.ok(oneVerifiedItems[0].label.includes("$(check)"), "the winner must use the verified icon");
    assert.ok(oneVerifiedItems[0].detail.includes("/ws/b → /ws/b-real"), "the winner's detail must show path → realPath");
    assert.ok(oneVerifiedItems[1].description.includes("2 probed"), "only the 2 unsuccessful workspaceFolder candidates are counted, not the winner");
    assert.ok(oneVerifiedItems[2].label.includes("aldc.yaml"));

    // A single, solitary workspaceFolder candidate (single-root project, the common case): the
    // collapsing logic still produces its one-line summary form (not a bare pass-through), and it
    // must still name "Mounted workspace folder" and count exactly the one probe.
    const singleUnsuccessful = resolution([
        candidate("workspaceFolder", "missing", { path: "/ws/only" })
    ]);
    const singleItems = buildResolverChainItems(singleUnsuccessful);
    assert.strictEqual(singleItems.length, 1);
    assert.ok(singleItems[0].label.includes("Mounted workspace folder"));
    assert.ok(singleItems[0].description.includes("1 probed"));

    console.log("BCQuality status resolver-chain tests passed.");
}

main();
