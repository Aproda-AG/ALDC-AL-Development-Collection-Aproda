const assert = require("assert");

// The toolkit layer must never be offered before the extension that applies it: an end-to-end run
// measured that the wrong order leaves BCQuality unreachable in the project. Until this was extracted,
// the correct order held only because the extension check happened to be the shorter code path.

const { sequenceStartupChecks } = require("../dist/startup/sequence");

function deferred() {
    let resolve;
    const promise = new Promise((r) => { resolve = r; });
    return { promise, resolve };
}

async function testLayerCheckWaitsForExtensionCheck() {
    const extension = deferred();
    const order = [];

    const sequenced = sequenceStartupChecks(
        extension.promise,
        () => true,
        async () => { order.push("layer"); }
    );

    // Give the microtask queue every chance to run the layer check early.
    await Promise.resolve();
    await Promise.resolve();
    assert.deepStrictEqual(order, [], "the layer check must not start while the extension check is pending");

    order.push("extension");
    extension.resolve();
    await sequenced;

    assert.deepStrictEqual(order, ["extension", "layer"], "the layer check must run only after the extension check settled");
}

// The extension check can hold the sequence for minutes; whether the layer check is still due has to be
// decided afterwards, against the state at that moment.
async function testGateIsEvaluatedAfterTheWait() {
    const extension = deferred();
    let due = false;
    let layerRuns = 0;

    const sequenced = sequenceStartupChecks(
        extension.promise,
        () => due,
        async () => { layerRuns += 1; }
    );

    due = true;
    extension.resolve();
    await sequenced;

    assert.strictEqual(layerRuns, 1, "the gate must be read after the wait, not captured before it");
}

async function testGateCanSkipTheLayerCheck() {
    let layerRuns = 0;
    await sequenceStartupChecks(Promise.resolve(), () => false, async () => { layerRuns += 1; });
    assert.strictEqual(layerRuns, 0, "a closed gate must skip the layer check entirely");
}

async function main() {
    await testLayerCheckWaitsForExtensionCheck();
    await testGateIsEvaluatedAfterTheWait();
    await testGateCanSkipTheLayerCheck();
    console.log("Startup check sequencing tests passed.");
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
