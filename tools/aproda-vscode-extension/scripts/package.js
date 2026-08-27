const { spawnSync } = require("child_process");
const path = require("path");
const packageJson = require("../package.json");

const output = path.join("dist", `aproda-aldc-${packageJson.version}.vsix`);
const vsce = path.join(__dirname, "..", "node_modules", "@vscode", "vsce", "vsce");
const result = spawnSync(process.execPath, [vsce, "package", "--out", output], { stdio: "inherit" });

process.exit(result.status ?? 1);