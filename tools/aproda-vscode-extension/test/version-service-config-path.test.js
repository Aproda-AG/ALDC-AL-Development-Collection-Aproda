const assert = require("assert");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const Module = require("module");

const vscodeMock = {
    workspace: {
        getConfiguration: () => ({ get: (_key, defaultValue) => defaultValue })
    },
    window: {
        createOutputChannel: () => ({ appendLine: () => { }, show: () => { }, dispose: () => { } })
    }
};
const originalLoad = Module._load;
Module._load = function (request, parent, isMain) {
    return request === "vscode" ? vscodeMock : originalLoad.call(this, request, parent, isMain);
};
const { VersionService } = require("../dist/version/service");
const { Logger } = require("../dist/log");
Module._load = originalLoad;

async function main() {
    const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-version-service-"));
    const logger = new Logger();
    const service = new VersionService(logger);
    try {
        // Consuming-project layout (post-T-33): config lives under .github, no root aldc.yaml.
        const consumingRoot = path.join(tempRoot, "consuming");
        await fs.mkdir(path.join(consumingRoot, ".github"), { recursive: true });
        await fs.writeFile(path.join(consumingRoot, ".github", "aldc.yaml"), "aproda:\n  layerVersion: github-marker\n");
        const consumingResult = await service.check(consumingRoot);
        assert.strictEqual(consumingResult.status, "invalid");
        assert.strictEqual(consumingResult.installed, "github-marker");

        // Fork layout (pre-T-33): config at the repo root, no .github directory at all.
        const forkRoot = path.join(tempRoot, "fork");
        await fs.mkdir(forkRoot, { recursive: true });
        await fs.writeFile(path.join(forkRoot, "aldc.yaml"), "aproda:\n  layerVersion: root-marker\n");
        const forkResult = await service.check(forkRoot);
        assert.strictEqual(forkResult.status, "invalid");
        assert.strictEqual(forkResult.installed, "root-marker");

        // Both present: .github must win (two-rung order), proving it is not a fallback-only check.
        const bothRoot = path.join(tempRoot, "both");
        await fs.mkdir(path.join(bothRoot, ".github"), { recursive: true });
        await fs.writeFile(path.join(bothRoot, ".github", "aldc.yaml"), "aproda:\n  layerVersion: github-marker\n");
        await fs.writeFile(path.join(bothRoot, "aldc.yaml"), "aproda:\n  layerVersion: root-marker\n");
        const bothResult = await service.check(bothRoot);
        assert.strictEqual(bothResult.installed, "github-marker");

        // Genuinely absent: neither location has a config file.
        const absentRoot = path.join(tempRoot, "absent");
        await fs.mkdir(absentRoot, { recursive: true });
        const absentResult = await service.check(absentRoot);
        assert.strictEqual(absentResult.status, "notInstalled");
    } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("Version service configuration path tests passed."));
