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
const { reconcileBcqualityWorkspace } = require("../dist/workspace/bcqualityRoot");
Module._load = originalLoad;

async function main() {
    const repositoryRoot = await fs.mkdtemp(path.join(os.tmpdir(), "aproda-aldc-workspace-"));
    const bcqualityRoot = path.join(path.dirname(repositoryRoot), "BCQuality-Aproda");
    const workspacePath = path.join(repositoryRoot, "project.code-workspace");
    try {
        await fs.writeFile(workspacePath, `{
  // Preserve this comment.
  "folders": [{ "name": "BCQuality", "path": "../bcquality-aproda" }],
  "settings": {}
}`);
        const logger = { info: () => undefined, error: () => undefined };
        await reconcileBcqualityWorkspace(repositoryRoot, bcqualityRoot, logger);
        const source = await fs.readFile(workspacePath, "utf8");
        assert.match(source, /Preserve this comment/);
        assert.match(source, /"path": "\.\.\/BCQuality-Aproda"/);
        assert.match(source, /"BCQUALITY_HOME":/);
        assert.match(source, /"files\.watcherExclude"/);
        assert.match(source, /"search\.exclude"/);
    } finally {
        await fs.rm(repositoryRoot, { recursive: true, force: true });
    }
}

main().then(() => console.log("BCQuality workspace tests passed."));