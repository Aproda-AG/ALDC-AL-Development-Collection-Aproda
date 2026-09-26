#!/usr/bin/env node
/**
 * ALDC Core Validator v1.2
 * Validates repository compliance against ALDC Core Spec v1.2.
 *
 * Checks:
 *   1. aldc.yaml exists and parses correctly
 *   2. .github/plans/ directory exists
 *   3. memory.md (global) exists
 *   4. Requirement sets are complete ({req_name}.spec.md + .architecture.md + .test-plan.md)
 *   5. Templates exist and are unmodified (optional hash check)
 *   6. Required agents, subagents, workflows, skills, instructions exist
 *   7. Copilot entrypoint coherence
 *
 * Usage:
 *   node tools/aldc-validate/index.js [--config aldc.yaml]
 *
 * Without --config the file is resolved two-rung (Aproda T-33): aldc.yaml lives at
 * <toolkitRoot>/aldc.yaml, i.e. .github/ in a consuming project and the repo root
 * in the fork/upstream layout.
 */

const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml"); // npm i js-yaml

const args = process.argv.slice(2);
const idx = args.indexOf("--config");
let configPath =
  idx !== -1 && args[idx + 1]
    ? args[idx + 1]
    : [".github/aldc.yaml", "aldc.yaml"].find((candidate) => fs.existsSync(candidate)) ?? "aldc.yaml";

const S = { errors: [], warnings: [], info: [] };

function error(msg) { S.errors.push(msg); }
function warn(msg) { S.warnings.push(msg); }
function info(msg) { S.info.push(msg); }

function fileExists(p) { return fs.existsSync(p); }
function readFile(p) { return fs.readFileSync(p, "utf8"); }

// ─── 1. Parse aldc.yaml ───────────────────────────────────────────
if (!fileExists(configPath)) {
  error(`aldc.yaml not found at ${configPath}`);
  report();
  process.exit(1);
}

let cfg;
try {
  cfg = yaml.load(readFile(configPath));
  info(`aldc.yaml parsed (core version: ${cfg.core?.version})`);
} catch (e) {
  error(`aldc.yaml parse error: ${e.message}`);
  report();
  process.exit(1);
}

const root = cfg.toolkitRoot === "." ? "" : cfg.toolkitRoot + "/";
const rules = cfg.validation?.rules || {};
function severity(rule) { return rules[rule] || "warn"; }
function issue(rule, msg) { severity(rule) === "error" ? error(msg) : warn(msg); }

// ─── 2. Plans directory ───────────────────────────────────────────
const plansRoot = cfg.plans?.root || ".github/plans";
if (!fileExists(plansRoot)) {
  issue("missingPlansDir", `Plans directory not found: ${plansRoot}`);
} else {
  info(`Plans directory exists: ${plansRoot}`);
}

// ─── 3. Global memory ────────────────────────────────────────────
const memoryFile = cfg.contracts?.globalMemory || "memory.md";
const memoryPath = path.join(plansRoot, memoryFile);
if (!fileExists(memoryPath)) {
  issue("missingGlobalMemory", `Global memory not found: ${memoryPath}`);
} else {
  info(`Global memory exists: ${memoryPath}`);
}

// ─── 4. Requirement sets completeness ────────────────────────────
if (fileExists(plansRoot)) {
  const contractTypes = cfg.contracts?.types || ["spec", "architecture", "test-plan"];
  const files = fs.readdirSync(plansRoot).filter(f => f.endsWith(".md") && f !== memoryFile);

  // Extract unique req_names
  const reqNames = new Set();
  const filesByReq = {};

  for (const f of files) {
    for (const type of contractTypes) {
      const suffix = `.${type}.md`;
      if (f.endsWith(suffix)) {
        const reqName = f.slice(0, -suffix.length);
        reqNames.add(reqName);
        if (!filesByReq[reqName]) filesByReq[reqName] = [];
        filesByReq[reqName].push(type);
      }
    }
  }

  for (const reqName of reqNames) {
    const found = filesByReq[reqName] || [];
    const missing = contractTypes.filter(t => !found.includes(t));
    if (missing.length > 0) {
      issue("incompleteRequirementSets",
        `Requirement "${reqName}" incomplete: missing ${missing.map(t => `${reqName}.${t}.md`).join(", ")}`);
    } else {
      info(`Requirement "${reqName}" has complete set (${contractTypes.length}/${contractTypes.length})`);
    }
  }

  if (reqNames.size === 0) {
    info("No requirement sets found in plans directory (may be initial setup)");
  }
}

// ─── 5. Templates ────────────────────────────────────────────────
const templates = cfg.required?.templates || [];
for (const t of templates) {
  const tp = root + t;
  if (!fileExists(tp)) {
    issue("missingTemplates", `Template not found: ${tp}`);
  } else {
    info(`Template exists: ${tp}`);
  }
}

// ─── 6. Required toolkit files ───────────────────────────────────

// 6a. Agents
const agents = cfg.required?.agents || [];
for (const a of agents) {
  const ap = root + a;
  if (!fileExists(ap)) {
    issue("missingToolkitFiles", `Agent not found: ${ap}`);
  } else {
    info(`Agent exists: ${ap}`);
  }
}

// 6b. Subagents
const subagents = cfg.required?.subagents || [];
for (const s of subagents) {
  const sp = root + s;
  if (!fileExists(sp)) {
    issue("missingToolkitFiles", `Subagent not found: ${sp}`);
  } else {
    info(`Subagent exists: ${sp}`);
  }
}

// 6c. Workflows
const workflows = cfg.required?.workflows || [];
for (const w of workflows) {
  const wp = root + w;
  if (!fileExists(wp)) {
    issue("missingToolkitFiles", `Workflow not found: ${wp}`);
  } else {
    info(`Workflow exists: ${wp}`);
  }
}

// 6d. Skills (required)
const requiredSkills = cfg.required?.skills?.required || [];
for (const sk of requiredSkills) {
  const skp = root + sk;
  if (!fileExists(skp)) {
    issue("missingSkills", `Required skill not found: ${skp}`);
  } else {
    info(`Required skill exists: ${skp}`);
  }
}

// 6e. Skills (recommended)
const recommendedSkills = cfg.required?.skills?.recommended || [];
for (const sk of recommendedSkills) {
  const skp = root + sk;
  if (!fileExists(skp)) {
    issue("missingRecommendedSkills", `Recommended skill not found: ${skp}`);
  } else {
    info(`Recommended skill exists: ${skp}`);
  }
}

// 6f. Instructions
const instructions = cfg.required?.instructions || [];
for (const i of instructions) {
  const ip = root + i;
  if (!fileExists(ip)) {
    issue("missingToolkitFiles", `Instruction not found: ${ip}`);
  } else {
    info(`Instruction exists: ${ip}`);
  }
}

// ─── 7. AL file naming convention ────────────────────────────────
// Verifies every *.al file in the project follows <ObjectName>.<ObjectType>.al.
// The narrow globs of type-specific instructions (al-performance, al-events,
// al-error-handling) depend on this pattern — a misnamed file silently loses
// its instructions.
const AL_OBJECT_TYPES = new Set([
  "Table", "TableExt",
  "Page", "PageExt", "PageCustomization",
  "Codeunit",
  "Report", "ReportExt",
  "Query",
  "XmlPort",
  "Enum", "EnumExt",
  "Interface",
  "ControlAddIn",
  "Profile",
  "PermissionSet", "PermissionSetExt",
  "Entitlement",
  "DotNet"
]);

function walkAlFiles(dir, acc) {
  if (!fileExists(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkAlFiles(full, acc);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".al")) {
      acc.push(full);
    }
  }
  return acc;
}

const alFiles = walkAlFiles(".", []);
const malformed = [];
for (const f of alFiles) {
  const base = path.basename(f);
  // Expected: <Name>.<Type>.al where <Type> is in AL_OBJECT_TYPES
  const parts = base.split(".");
  if (parts.length < 3 || parts[parts.length - 1].toLowerCase() !== "al") {
    malformed.push(f);
    continue;
  }
  const type = parts[parts.length - 2];
  if (!AL_OBJECT_TYPES.has(type)) {
    malformed.push(f);
  }
}

if (alFiles.length === 0) {
  info("AL naming: no .al files found in project (skipping check)");
} else if (malformed.length === 0) {
  info(`AL naming: all ${alFiles.length} .al files follow <Name>.<Type>.al`);
} else {
  for (const f of malformed) {
    issue("malformedAlFileName",
      `AL file does not follow <ObjectName>.<ObjectType>.al pattern: ${f}`);
  }
  info(`AL naming: ${alFiles.length - malformed.length}/${alFiles.length} files compliant`);
}

// ─── 8. Copilot entrypoint coherence ─────────────────────────────
// Three modes (cfg.copilotEntrypointMode, default "mirror"):
//   "mirror"   — the entrypoint must be byte-identical to its source (install.js
//                copies source -> entrypoint; any drift is a stale copy).
//   "trimmed"  — the entrypoint is an intentional lean subset of the source (the
//                ~31% always-on trim): we no longer require byte-identity, only
//                that it exists, is non-empty, and is genuinely smaller than the
//                source (a larger/equal "trim" means it went stale, not lean).
//   "extended" — the entrypoint is the maintained artifact and deliberately adds
//                content the source does not carry (e.g. a fork layer). Size is
//                not a staleness signal here, so only existence and non-emptiness
//                are checked. Use this instead of silencing the rule.
const entrypoint = cfg.copilotEntrypoint;
const source = cfg.copilotSource;
const entrypointMode = cfg.copilotEntrypointMode || "mirror";

if (entrypoint && !fileExists(entrypoint)) {
  issue("copilotEntrypointCoherence", `Copilot entrypoint not found: ${entrypoint}`);
} else if (entrypoint && source) {
  const sourcePath = root + source;
  if (fileExists(entrypoint) && fileExists(sourcePath)) {
    const ep = readFile(entrypoint).trim();
    const src = readFile(sourcePath).trim();
    if (entrypointMode === "trimmed") {
      if (ep.length === 0) {
        issue("copilotEntrypointCoherence", `Copilot entrypoint is empty: ${entrypoint}`);
      } else if (ep.length >= src.length) {
        issue("copilotEntrypointCoherence",
          `Copilot entrypoint is declared "trimmed" but is not smaller than its source (${entrypoint} ≥ ${sourcePath}) — likely stale, not a trim`);
      } else {
        info(`Copilot entrypoint is an intentional trim (${ep.length} vs ${src.length} source chars)`);
      }
    } else if (entrypointMode === "extended") {
      if (ep.length === 0) {
        issue("copilotEntrypointCoherence", `Copilot entrypoint is empty: ${entrypoint}`);
      } else {
        info(`Copilot entrypoint deliberately extends its source (${ep.length} vs ${src.length} source chars)`);
      }
    } else if (ep !== src) {
      issue("copilotEntrypointCoherence",
        `Copilot entrypoint drift detected: ${entrypoint} differs from ${sourcePath}`);
    } else {
      info("Copilot entrypoint is in sync with source");
    }
  }
}

// ─── 9. Aproda layer coherence (D-46 / D-47, E-006 T-6) ──────────
// Three checks, all severity "warn" until the T-10/T-11 catalog sweep promotes
// them to "error" (decisions.aproda.md D-47) — the fork ships known-stale
// catalogs today, so starting at "error" would fail every build immediately.

// Generic recursive file walker (any extension), skipping noise directories.
const APRODA_SKIP_DIRS = new Set(["node_modules", "archive", "_A-ALDC-Plans", ".AL-Go"]);
function walkAllFiles(dir, acc) {
  if (!fileExists(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    if (APRODA_SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkAllFiles(full, acc);
    } else if (entry.isFile()) {
      acc.push(full);
    }
  }
  return acc;
}
const repoFiles = walkAllFiles(".", []).map(f => f.replace(/\\/g, "/").replace(/^\.\//, ""));

// B-36: fork-only artifacts (neverTouch, or matched by no allow rule at all in
// aproda-sync.json) must not warn as "missing" in a project — they were never
// meant to ship there. Derived from the manifest so no path list is hardcoded.
const isProjectLayout = root !== "";
const aprodaSyncManifest = (() => {
  const p = root + "tools/aproda-sync/aproda-sync.json";
  if (!fileExists(p)) return null;
  try {
    const raw = readFile(p).replace(/(^|[^:"])\/\/.*$/gm, "$1").replace(/,(\s*[\]}])/g, "$1");
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
})();
function globToRegex(glob) {
  const esc = glob.replace(/\\/g, "/").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp("^" + esc
    // "**/" spans zero or more directories: without this a leading "**/" would demand a slash and
    // never match a root-level path such as readme.aproda.md.
    .replace(/\\\*\\\*\//g, "(?:.*/)?")
    .replace(/\/\\\*\\\*/g, "(/.*)?")
    .replace(/\\\*\\\*/g, ".*")
    .replace(/\\\*/g, "[^/]*")
    .replace(/\\\?/g, "[^/]") + "$");
}
function isForkOnly(logicalPath) {
  if (!aprodaSyncManifest) return false; // manifest unreadable -> don't suppress, stay honest
  const l = logicalPath.replace(/\/$/, "");
  const matchesAny = (globs) => (globs || []).some(g => globToRegex(g).test(l));
  const allowed = matchesAny(aprodaSyncManifest.includeGlobs)
    || (aprodaSyncManifest.includeFiles || []).includes(l)
    || (aprodaSyncManifest.inPlaceEdits || []).includes(l);
  const denied = matchesAny(aprodaSyncManifest.neverTouch)
    && !(aprodaSyncManifest.neverTouchExceptions || []).includes(l);
  return !allowed || denied;
}

// 9a. catalogCoherence — flat catalogs (agents/prompts/instructions) + the
// nested skills catalog. A file on disk not linked by name in its catalog, or
// a catalog link that resolves to nothing, is an issue either direction.
function extractLinkedFiles(text, suffixRe) {
  const re = new RegExp("\\(([\\w.\\-]+\\." + suffixRe + ")\\)", "g");
  const out = new Set();
  let m;
  while ((m = re.exec(text))) out.add(m[1]);
  return out;
}

function checkFlatCatalog(kind, dirRel, suffix, catalogRel) {
  const dirPath = root + dirRel;
  const catalogPath = root + catalogRel;
  if (!fileExists(dirPath) || !fileExists(catalogPath)) return;
  const onDisk = new Set(fs.readdirSync(dirPath).filter(f => f.endsWith("." + suffix)));
  const linked = extractLinkedFiles(readFile(catalogPath), suffix.replace(/\./g, "\\."));
  for (const f of onDisk) {
    if (!linked.has(f)) issue("catalogCoherence", `${kind} exists on disk but is not linked from ${catalogRel}: ${f}`);
  }
  for (const f of linked) {
    if (!onDisk.has(f)) issue("catalogCoherence", `${catalogRel} links a ${kind} that does not exist on disk: ${f}`);
  }
}

checkFlatCatalog("agent", "agents", "agent.md", "agents/index.md");
checkFlatCatalog("workflow", "prompts", "prompt.md", "prompts/index.md");
checkFlatCatalog("instruction", "instructions", "instructions.md", "instructions/index.md");

{
  const skillsDir = root + "skills";
  const catalogPath = root + "skills/index.md";
  if (fileExists(skillsDir) && fileExists(catalogPath)) {
    const onDisk = new Set(
      fs.readdirSync(skillsDir, { withFileTypes: true })
        .filter(e => e.isDirectory() && e.name.startsWith("skill-") && fileExists(path.join(skillsDir, e.name, "SKILL.md")))
        .map(e => e.name)
    );
    const linkRe = /\((skill-[\w-]+)\/SKILL\.md\)/g;
    const linked = new Set();
    let m;
    const catalogText = readFile(catalogPath);
    while ((m = linkRe.exec(catalogText))) linked.add(m[1]);
    for (const s of onDisk) {
      if (!linked.has(s)) issue("catalogCoherence", `Skill exists on disk but is not linked from skills/index.md: ${s}`);
    }
    for (const s of linked) {
      if (onDisk.has(s)) continue;
      if (isProjectLayout && isForkOnly("skills/" + s)) continue;
      issue("catalogCoherence", `skills/index.md links a skill that does not exist on disk: ${s}`);
    }
  }
}

// 9b. versionCoherence — "ALDC Core vX.Y" literals, scoped to Aproda-owned
// paths only (*.aproda.*, skill-aproda-*/**, inPlaceEdits, the entrypoint,
// aldc.yaml itself). ~19 inherited Upstream files also carry a stale version
// literal (Findings 02 §3) — those are an upstream-PR concern (E-006 Phase 4),
// deliberately out of scope here so this rule never asks the fork to sweep a
// defect it did not cause.
{
  const coreVersionMatch = /^(\d+)\.(\d+)/.exec(String((cfg.core && cfg.core.version) || ""));
  if (coreVersionMatch) {
    const coreMajor = coreVersionMatch[1], coreMinor = coreVersionMatch[2];

    const scoped = new Set();
    if (entrypoint && fileExists(entrypoint)) scoped.add(entrypoint);
    if (fileExists(configPath)) scoped.add(configPath);
    for (const f of repoFiles) {
      if (/\.aproda\./.test(path.basename(f))) scoped.add(f);
      if (/(^|\/)skill-aproda-[^/]+\//.test(f)) scoped.add(f);
    }

    const syncManifestPath = root + "tools/aproda-sync/aproda-sync.json";
    if (fileExists(syncManifestPath)) {
      try {
        const raw = readFile(syncManifestPath)
          .replace(/(^|[^:"])\/\/.*$/gm, "$1")
          .replace(/,(\s*[\]}])/g, "$1"); // JSONC allows trailing commas; strict JSON does not
        const syncManifest = JSON.parse(raw);
        for (const logical of syncManifest.inPlaceEdits || []) {
          if (logical === "copilot-instructions.md") continue; // already covered via copilotEntrypoint
          const p = root + logical;
          if (fileExists(p)) scoped.add(p);
        }
      } catch (e) {
        warn(`versionCoherence: could not parse ${syncManifestPath}: ${e.message}`);
      }
    }

    const versionRe = /ALDC Core v(\d+)\.(\d+)/g;
    for (const f of scoped) {
      if (!fileExists(f) || fs.statSync(f).isDirectory()) continue;
      const text = readFile(f);
      let m;
      while ((m = versionRe.exec(text))) {
        if (m[1] !== coreMajor || m[2] !== coreMinor) {
          issue("versionCoherence", `${f} says "ALDC Core v${m[1]}.${m[2]}" but core.version is ${coreMajor}.${coreMinor}`);
        }
      }
    }
  }
}

// 9c. aprodaInventoryCoherence — every net-new Aproda file/folder must be
// named inside readme.aproda.md's "What lives here" section, and vice versa.
{
  const readmePath = (cfg.aproda && cfg.aproda.inventory) || (root + "readme.aproda.md");
  if (fileExists(readmePath)) {
    const readmeText = readFile(readmePath);
    const sectionMatch = /## What lives here[\s\S]*?(?=\n---|\n## |$)/.exec(readmeText);
    const section = sectionMatch ? sectionMatch[0] : readmeText;

    for (const f of repoFiles) {
      if (!/\.aproda\./.test(path.basename(f))) continue;
      if (!section.includes(path.basename(f))) {
        issue("aprodaInventoryCoherence", `${f} is a net-new Aproda file but its name does not appear in readme.aproda.md's inventory`);
      }
    }

    const skillsDir = root + "skills";
    if (fileExists(skillsDir)) {
      const aprodaSkillDirs = fs.readdirSync(skillsDir, { withFileTypes: true })
        .filter(e => e.isDirectory() && e.name.startsWith("skill-aproda-"))
        .map(e => e.name);
      for (const s of aprodaSkillDirs) {
        if (!section.includes(s)) {
          issue("aprodaInventoryCoherence", `skills/${s}/ is an Aproda skill but its name does not appear in readme.aproda.md's inventory`);
        }
      }
    }

    // Reverse: backtick-quoted, slash-containing "aproda" paths mentioned in the
    // section should resolve to a real file. The table itself mixes two styles
    // (some rows carry a ".github/" prefix — the dotGithub exceptions that stay
    // under .github/ on both fork and project layouts — others don't — the
    // regular fork-root paths), so try the reference both as-is and prefixed
    // with `root`, and accept either resolving.
    const codeSpanRe = /`([^`]*aproda[^`]*)`/g;
    let m;
    while ((m = codeSpanRe.exec(section))) {
      let ref = m[1].trim();
      if (!ref.includes("/") || ref.startsWith("/")) continue; // prose mention or external (e.g. user-memory) path
      ref = ref.replace(/\/$/, "");
      if (!ref) continue;
      const candidates = [ref, root + ref];
      const resolved = candidates.some(c => fileExists(c) || fileExists(c + "/SKILL.md"));
      if (!resolved) {
        const logical = ref.replace(/^\.github\//, "");
        if (isProjectLayout && isForkOnly(logical)) continue;
        issue("aprodaInventoryCoherence", `readme.aproda.md's inventory references "${m[1]}" which does not resolve to an existing path (checked ${candidates.join(", ")})`);
      }
    }
  }
}

// ─── Report ──────────────────────────────────────────────────────
function report() {
  console.log("\n╔══════════════════════════════════════════╗");
  console.log("║     ALDC Core Validator v1.2             ║");
  console.log("╚══════════════════════════════════════════╝\n");

  if (S.info.length) {
    console.log("ℹ️  Info:");
    S.info.forEach(m => console.log(`   ✓ ${m}`));
    console.log();
  }
  if (S.warnings.length) {
    console.log("⚠️  Warnings:");
    S.warnings.forEach(m => console.log(`   ⚠ ${m}`));
    console.log();
  }
  if (S.errors.length) {
    console.log("❌ Errors:");
    S.errors.forEach(m => console.log(`   ✗ ${m}`));
    console.log();
  }

  const total = S.errors.length + S.warnings.length;
  if (S.errors.length === 0) {
    console.log(`✅ ALDC Core v1.2 COMPLIANT (${S.warnings.length} warning(s))`);
  } else {
    console.log(`❌ NOT COMPLIANT — ${S.errors.length} error(s), ${S.warnings.length} warning(s)`);
  }

  // Summary table
  console.log("\n┌────────────────────┬───────┐");
  console.log("│ Check              │ Count │");
  console.log("├────────────────────┼───────┤");
  console.log(`│ Agents             │ ${agents.length.toString().padStart(5)} │`);
  console.log(`│ Subagents          │ ${subagents.length.toString().padStart(5)} │`);
  console.log(`│ Workflows          │ ${workflows.length.toString().padStart(5)} │`);
  console.log(`│ Skills (required)  │ ${requiredSkills.length.toString().padStart(5)} │`);
  console.log(`│ Skills (recommend) │ ${recommendedSkills.length.toString().padStart(5)} │`);
  console.log(`│ Instructions       │ ${instructions.length.toString().padStart(5)} │`);
  console.log(`│ Templates          │ ${templates.length.toString().padStart(5)} │`);
  console.log("└────────────────────┴───────┘");

  process.exit(S.errors.length > 0 ? 1 : 0);
}

report();
