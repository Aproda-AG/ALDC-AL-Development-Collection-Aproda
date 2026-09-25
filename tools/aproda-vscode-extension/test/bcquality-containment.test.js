const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");

const { resolveContained } = require("../dist/bcquality/containment");

async function makeClone(root) {
    await fs.mkdir(path.join(root, "skills"), { recursive: true });
    await fs.writeFile(path.join(root, "skills", "entry.md"), "# entry");
}

async function testLegitimateNestedPathAllowed(scratch) {
    const root = path.join(scratch, "clone-1");
    await makeClone(root);

    const result = await resolveContained(root, "skills/entry.md");
    assert.strictEqual(result.ok, true, "a legitimate nested relative path must be allowed");
    assert.strictEqual(path.resolve(result.absolutePath), path.resolve(root, "skills", "entry.md"));
}

// Real fixture: a sensitive file sitting just outside the clone root, proven unreachable via "..".
async function testParentTraversalRejected(scratch) {
    const root = path.join(scratch, "clone-2");
    await makeClone(root);
    const secret = path.join(scratch, "secret.txt");
    await fs.writeFile(secret, "TOP SECRET");

    const result = await resolveContained(root, "../secret.txt");
    assert.strictEqual(result.ok, false, "'..' traversal must be rejected");
    assert.strictEqual(result.absolutePath, undefined);

    // Prove the rejection is not merely cosmetic: the file must never actually be readable through this path.
    const wouldHaveResolvedTo = path.resolve(root, "../secret.txt");
    assert.strictEqual(path.resolve(secret), wouldHaveResolvedTo, "fixture sanity: '..' really does reach the secret file");
}

async function testAbsolutePathRejected(scratch) {
    const root = path.join(scratch, "clone-3");
    await makeClone(root);
    const secret = path.join(scratch, "secret-abs.txt");
    await fs.writeFile(secret, "TOP SECRET");

    const result = await resolveContained(root, secret);
    assert.strictEqual(result.ok, false, "an absolute path must be rejected outright");
}

async function testMixedSeparatorTraversalRejected(scratch) {
    const root = path.join(scratch, "clone-4");
    await makeClone(root);
    const secret = path.join(scratch, "secret-mixed.txt");
    await fs.writeFile(secret, "TOP SECRET");

    // Deliberately mixes '/' and '\' in one traversal string.
    const result = await resolveContained(root, "sub/..\\../secret-mixed.txt");
    assert.strictEqual(result.ok, false, "traversal using mixed separators must be rejected");
}

async function testSymlinkEscapeRejected(scratch) {
    const root = path.join(scratch, "clone-5");
    await makeClone(root);
    const secret = path.join(scratch, "secret-link-target.txt");
    await fs.writeFile(secret, "TOP SECRET");

    const linkPath = path.join(root, "escape-link");
    try {
        await fs.symlink(secret, linkPath, process.platform === "win32" ? "file" : undefined);
    } catch (error) {
        // Symlink creation can be restricted (e.g. no elevation on Windows); skip rather than fail the suite.
        console.log(`Skipped symlink-escape test: ${error.message}`);
        return;
    }
    const result = await resolveContained(root, "escape-link");
    assert.strictEqual(result.ok, false, "a symlink resolving outside the clone root must be rejected even though the requested path is nested");
}

// Windows-only: a naive `startsWith(root)` containment check (without a separator boundary, and without
// case-insensitive comparison) would incorrectly accept a sibling directory whose name merely starts with
// the root's own name.
async function testCaseVariantSiblingPrefixRejected(scratch) {
    if (process.platform !== "win32") {
        return;
    }
    const root = path.join(scratch, "Clone-6");
    await makeClone(root);
    const siblingSecretDir = path.join(scratch, "clone-6-evil");
    await fs.mkdir(siblingSecretDir, { recursive: true });
    await fs.writeFile(path.join(siblingSecretDir, "secret.txt"), "TOP SECRET");

    const result = await resolveContained(root, "../clone-6-evil/secret.txt");
    assert.strictEqual(result.ok, false, "a case-variant sibling directory sharing the root's name as a prefix must be rejected");
}

// FIX 3 (Windows only): an NTFS alternate data stream must be rejected explicitly, not merely fail later
// via fs.stat's ENOENT. A legitimate nested path must keep working alongside this new check.
async function testAlternateDataStreamRejected(scratch) {
    if (process.platform !== "win32") {
        return;
    }
    const root = path.join(scratch, "clone-7");
    await makeClone(root);

    const result = await resolveContained(root, "skills/entry.md:hidden");
    assert.strictEqual(result.ok, false, "an NTFS alternate data stream suffix must be rejected");

    const legitimate = await resolveContained(root, "skills/entry.md");
    assert.strictEqual(legitimate.ok, true, "a legitimate nested path must still be allowed alongside the ADS check");
}

async function main() {
    const scratch = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-containment-"));
    try {
        await testLegitimateNestedPathAllowed(scratch);
        await testParentTraversalRejected(scratch);
        await testAbsolutePathRejected(scratch);
        await testMixedSeparatorTraversalRejected(scratch);
        await testSymlinkEscapeRejected(scratch);
        await testCaseVariantSiblingPrefixRejected(scratch);
        await testAlternateDataStreamRejected(scratch);
    } finally {
        await fs.rm(scratch, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality path containment tests passed."));
