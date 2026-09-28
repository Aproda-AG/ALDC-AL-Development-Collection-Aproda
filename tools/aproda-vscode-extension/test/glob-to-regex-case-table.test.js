const assert = require("assert");
const { globToRegex } = require("../../aldc-validate/globToRegex");

// Same case table as tools/aproda-sync/Test-ConvertGlobToRegex.ps1 (kept as two lists,
// not one shared file, because PowerShell has no require() of a JS module — but every
// case is exercised in BOTH runtimes). Guards the historical glob bug (B-36/B-37/B-12):
// a leading '**/' must match root-level paths (no directory segment at all), and a bare
// '*' must never cross a '/'.
const cases = [
    ["**/*.aproda.*", "readme.aproda.md", true, "root-level file matches a leading **/ glob (B-36/B-37/B-12)"],
    ["**/*.aproda.*", "a/b/readme.aproda.md", true, "nested file matches a leading **/ glob"],
    ["**/*.aproda.*", "readme.md", false, "file without the .aproda. infix must not match"],
    ["*.md", "readme.md", true, "bare * matches a root-level filename"],
    ["*.md", "a/readme.md", false, "bare * must not cross a / into a parent directory"],
    ["skills/skill-aproda-*/**", "skills/skill-aproda-foo", true, "trailing /** matches the folder itself (zero-deep)"],
    ["skills/skill-aproda-*/**", "skills/skill-aproda-foo/bar/baz.md", true, "trailing /** matches nested content"],
    ["skills/skill-aproda-*/**", "skills/skill-other/bar.md", false, "a differently named skill folder must not match"],
    ["tools/aproda-ps-xliffsync/**", "tools/aproda-ps-xliffsync/README.md", true, "named tool folder, nested file"],
    ["tools/aproda-ps-xliffsync/**", "tools/aproda-ps-xliffsync", true, "named tool folder, the folder itself"]
];

function main() {
    for (const [glob, candidatePath, expected, description] of cases) {
        const actual = globToRegex(glob).test(candidatePath);
        assert.strictEqual(actual, expected, `${description} — globToRegex(${JSON.stringify(glob)}).test(${JSON.stringify(candidatePath)})`);
    }
    console.log(`All ${cases.length} globToRegex case(s) passed.`);
}

main();
