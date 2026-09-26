const assert = require("assert");

// The extension host runs with NODE_TLS_REJECT_UNAUTHORIZED=0 (VS Code verifies certificates itself).
// A spawned Node process inherits that and stops checking certificates altogether, so `npm install`
// would fetch packages over an unverified TLS connection even though npm's own strict-ssl is on.

const { childEnvironment } = require("../dist/process");

const original = process.env.NODE_TLS_REJECT_UNAUTHORIZED;
try {
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
    process.env.APRODA_TLS_PROBE_KEEP = "keep-me";

    const environment = childEnvironment();
    assert.ok(!("NODE_TLS_REJECT_UNAUTHORIZED" in environment), "the insecure TLS override must not reach a child process");
    assert.strictEqual(environment.APRODA_TLS_PROBE_KEEP, "keep-me", "every other inherited variable must survive");
    assert.strictEqual(process.env.NODE_TLS_REJECT_UNAUTHORIZED, "0", "the extension host's own environment must not be mutated");
} finally {
    delete process.env.APRODA_TLS_PROBE_KEEP;
    if (original === undefined) {
        delete process.env.NODE_TLS_REJECT_UNAUTHORIZED;
    } else {
        process.env.NODE_TLS_REJECT_UNAUTHORIZED = original;
    }
}

console.log("Child process TLS environment tests passed.");
