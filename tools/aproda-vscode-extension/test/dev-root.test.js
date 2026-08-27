const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const { proposeDevRoot } = require("../dist/env/devRoot");

async function main() {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-dev-root-"));
    try {
        const repositoryRoot = path.join(tempRoot, "Customer", "Project");
        await fs.mkdir(repositoryRoot, { recursive: true });
        const parsed = path.parse(repositoryRoot);
        const firstSegment = path.relative(parsed.root, repositoryRoot).split(path.sep).filter(Boolean)[0];
        assert.strictEqual(await proposeDevRoot(repositoryRoot), path.join(parsed.root, firstSegment));
        assert.strictEqual(await proposeDevRoot(undefined), undefined);
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("Developer root tests passed."));