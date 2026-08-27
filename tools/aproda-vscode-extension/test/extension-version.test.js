const assert = require("assert");
const { compareExtensionVersions } = require("../dist/extensionUpdate/version");

assert.strictEqual(compareExtensionVersions("0.1.0", "0.1.1"), -1);
assert.strictEqual(compareExtensionVersions("0.1.10", "0.1.9"), 1);
assert.strictEqual(compareExtensionVersions("1.0.0", "1.0.0"), 0);
assert.strictEqual(compareExtensionVersions("1.0.0-beta.2", "1.0.0-beta.10"), -1);
assert.strictEqual(compareExtensionVersions("1.0.0-rc.1", "1.0.0"), -1);

console.log("Extension version comparison tests passed.");