/**
 * Pure glob -> RegExp translation, extracted out of index.js so it is unit-testable
 * without executing the whole validator (index.js has no module.exports / require.main
 * guard and runs its checks immediately on require).
 *
 * Order matters: '**\/' before '/**' before '**'. '**\/' spans zero or more directories:
 * without this a leading '**\/' would demand a literal slash and a root-level path such
 * as readme.aproda.md would silently never match (the shipped-3-times B-36/B-37/B-12 bug).
 */
function globToRegex(glob) {
  const esc = glob.replace(/\\/g, "/").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp("^" + esc
    .replace(/\\\*\\\*\//g, "(?:.*/)?")
    .replace(/\/\\\*\\\*/g, "(/.*)?")
    .replace(/\\\*\\\*/g, ".*")
    .replace(/\\\*/g, "[^/]*")
    .replace(/\\\?/g, "[^/]") + "$");
}

module.exports = { globToRegex };
