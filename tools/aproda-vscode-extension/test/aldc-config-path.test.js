const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const vscodeMock = {
    workspace: {
        textDocuments: [],
        getConfiguration: () => ({ get: (_key, defaultValue) => defaultValue })
    }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { resolveConfigurationPath } = require("../dist/env/gitRoot");
Module._load = originalLoad;

async function main() {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-config-path-"));
    try {
        const bothRoot = path.join(tempRoot, "both");
        await fs.mkdir(path.join(bothRoot, ".github"), { recursive: true });
        await fs.writeFile(path.join(bothRoot, ".github", "aldc.yaml"), "toolkitRoot: .github\n");
        await fs.writeFile(path.join(bothRoot, "aldc.yaml"), "toolkitRoot: .\n");
        assert.strictEqual(await resolveConfigurationPath(bothRoot), path.join(bothRoot, ".github", "aldc.yaml"));

        const rootOnlyRoot = path.join(tempRoot, "root-only");
        await fs.mkdir(rootOnlyRoot, { recursive: true });
        await fs.writeFile(path.join(rootOnlyRoot, "aldc.yaml"), "toolkitRoot: .\n");
        assert.strictEqual(await resolveConfigurationPath(rootOnlyRoot), path.join(rootOnlyRoot, "aldc.yaml"));

        const githubOnlyRoot = path.join(tempRoot, "github-only");
        await fs.mkdir(path.join(githubOnlyRoot, ".github"), { recursive: true });
        await fs.writeFile(path.join(githubOnlyRoot, ".github", "aldc.yaml"), "toolkitRoot: .github\n");
        assert.strictEqual(await resolveConfigurationPath(githubOnlyRoot), path.join(githubOnlyRoot, ".github", "aldc.yaml"));

        const neitherRoot = path.join(tempRoot, "neither");
        await fs.mkdir(neitherRoot, { recursive: true });
        assert.strictEqual(await resolveConfigurationPath(neitherRoot), undefined);
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("ALDC config path resolution tests passed."));
