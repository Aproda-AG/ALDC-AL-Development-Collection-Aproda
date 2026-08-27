const assert = require("assert");
const { compareLayerVersions } = require("../dist/version/compare");

assert.strictEqual(compareLayerVersions("1.2.0_aproda.9", "1.2.0_aproda.10"), -1);
assert.strictEqual(compareLayerVersions("1.2.0_aproda.10", "1.2.0_aproda.9"), 1);
assert.strictEqual(compareLayerVersions("1.2.0_aproda.9", "1.2.0_aproda.9"), 0);
assert.strictEqual(compareLayerVersions("invalid", "1.2.0_aproda.9"), undefined);

console.log("Version comparison tests passed.");
