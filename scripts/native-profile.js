#!/usr/bin/env node
'use strict';

// Project the canonical Copilot content at install time. Never edit foundation,
// Claude distributions or canonical agents to select a different tool surface.
const fs = require('fs');
const path = require('path');
const SEARCH = ['al_symbolsearch', 'al_getdiagnostics'];
const BUILD = [...SEARCH, 'al_downloadsymbols', 'al_build'];
const DEBUG = ['al_debug', 'al_setbreakpoint', 'al_snapshotdebugging'];
const roles = {
  'al-architect': [SEARCH, 'Resolve architectural viability and dependencies; consume graph evidence. Delegate exact implementation declarations.'],
  'al-planning-subagent': [SEARCH, 'Resolve material planning gaps and reuse approved evidence; do not reopen settled design decisions.'],
  'al-developer': [[...BUILD, ...DEBUG], 'Own scoped implementation, dependency setup, builds, tests and optional graph operations through your existing terminal.'],
  'al-implement-subagent': [BUILD, 'Own scoped TDD implementation, dependency setup, builds and optional graph operations through your existing terminal.'],
  'al-review-subagent': [SEARCH, 'Read sources and actual implementation evidence. Diagnostics, fresh builds and runtime tests are different claims. Do not execute builds, tests, debugging or graph extraction.'],
  'dredd': [SEARCH, 'Remain independent: choose the audit question, inspect raw evidence and source yourself, and request a bounded graph operation from an implementation owner when needed.'],
  'al-triage': [[...SEARCH, 'al_downloadsymbols', ...DEBUG], 'Diagnose within the existing read-only-on-code scope; use authorized debugging, consume graph results, and hand implementation to Developer.'],
  'al-presales': [['al_symbolsearch'], 'Use bounded discovery only when feasibility or an estimate needs it; consume relevant findings without compiling or running graph commands.'],
  'al-agent-builder': [SEARCH, 'Discover relevant SDK objects and diagnostics; delegate build and graph work to an implementation owner. Keep existing agent models and responsibilities.'],
  'al-conductor': [[], 'Coordinate the existing Planning → Implementation → Review → Commit flow. Route capability questions to their owners and carry raw-result references into existing phase artifacts; never execute native or graph operations yourself.'],
};

function project(relative, input) {
  const rel = relative.replace(/\\/g, '/');
  if (!/^(agents\/[^/]+\.agent|prompts\/[^/]+\.prompt)\.md$/.test(rel)) return input;
  let text = input.toString('utf8');
  // Windows checkouts can use CRLF. Parse normalized lines, then restore the
  // input convention so the unchanged workflow body remains byte-identical.
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  text = text.replace(/\r\n/g, '\n');
  const end = text.indexOf('\n---', 3);
  if (!text.startsWith('---\n') || end < 0) throw new Error(`Invalid frontmatter: ${rel}`);
  let front = text.slice(0, end);
  let body = text.slice(end + 4);
  const role = path.basename(rel).replace(/\.(agent|prompt)\.md$/, '');
  const isAgent = rel.startsWith('agents/');
  if (isAgent && !roles[role]) throw new Error(`Native role assignment missing: ${role}`);
  const grant = isAgent ? roles[role][0] :
    role === 'al-build' ? BUILD : role === 'al-initialize' ? [...SEARCH, 'al_downloadsymbols'] :
    role === 'al-memory.create' ? [] : SEARCH;
  const toolLine = front.match(/^tools: \[(.*)\]$/m);
  if (!toolLine) throw new Error(`Expected explicit tools list: ${rel}`);
  const tools = toolLine[1].split(',').map(s => s.trim()).filter(s =>
    !/ms-dynamics-smb\.al\/|al-symbols-mcp\/|sshadowsdk\.al-lsp-for-agents\/|bc[-_]?atlas/i.test(s));
  if (!tools.some(t => t === 'read' || t === 'read/readFile')) tools.push('read/readFile');
  if (role === 'al-spec.create' && !tools.includes('edit/createFile')) tools.push('edit/createFile');
  tools.push(...grant.map(t => `ms-dynamics-smb.al/${t}`));
  front = front.replace(toolLine[0], `tools: [${[...new Set(tools)].join(', ')}]`);
  body = body.split('al_get_diagnostics').join('al_getdiagnostics');
  if (role === 'al-developer') {
    const first = body.indexOf('## Tool surface (authoritative');
    const last = body.indexOf('## CAN / CANNOT', first);
    if (first < 0 || last < 0) throw new Error('Developer tool section changed; review native projection.');
    body = body.slice(0, first) + '## Tool surface\n\nUse the granted native AL tools under the shared native contract. Build with `al_build`; an existing ALTool terminal task is a fallback after checking installed help. Publishing requires separate authorization. Permission-set generation and profiling use discovered commands or human steps, never invented tools.\n\n' + body.slice(last);
    body = body.split(' + **`bclsp_codeQualityDiagnostics`**').join('').split(' + `bclsp_codeQualityDiagnostics`').join('')
      .split('navigate via AL LSP').join('navigate via available native AL capabilities')
      .split('build in the terminal').join('build with `al_build` or the approved terminal fallback');
    front = front.replace('builds via the terminal', 'builds with native AL tools or the terminal');
  }
  body = body.split('`al_symbolsearch` / `bclsp_documentSymbols`').join('`al_symbolsearch` and target-matched source')
    .split('`al-symbols-mcp/*` (`al_packages`, `al_search_objects`, `al_get_object_definition`)').join('`al_symbolsearch`, app.json and target-matched source')
    .split('`al-symbols-mcp/*` (`al_search_objects`, `al_get_object_definition`)').join('`al_symbolsearch` and target-matched source')
    .split('al-symbols-mcp/al_search_objects').join('al_symbolsearch')
    .split('`al-symbols-mcp/*`').join('target-matched source')
    .split('`al_getdiagnostics` + `bclsp_codeQualityDiagnostics`').join('`al_getdiagnostics`')
    .split('`al_search_objects` / `al_symbolsearch` + `bclsp_goToDefinition`').join('`al_symbolsearch` and target-matched source')
    .split('`bclsp_findReferences` / `bclsp_incomingCalls` / `bclsp_prepareCallHierarchy`').join('target-matched source and available native navigation; request bounded graph evidence if needed')
    .split(' / `bclsp_findReferences`').join(' and available native navigation');
  if (role === 'al-spec.create') body = body.replace('download symbols first if absent', 'ask the implementation/setup owner to download symbols if absent');
  const duty = isAgent ? roles[role][1] : role === 'al-spec.create' ?
    'Write the canonical specification in the existing plans folder. Propose missing dependencies; only the implementation/setup owner changes app.json or downloads symbols. An uncertain test dependency does not prevent drafting the spec; retain unresolved facts in Open Questions.' :
    'Keep this workflow’s existing artifacts and approvals. Use only the native operations declared here; graph execution belongs to Developer/Implementer.';
  const notice = '\n\n## BC29 native capability contract\n\n' +
    'Profile: **bc29-native**, GitHub Copilot Chat in VS Code only. Before your first tool, dependency or evidence decision under this profile, read [the native tool contract](../docs/framework/native-al-tools.md). Apply its role scope, optional-provider rules, compatibility checks and evidence limits; reuse it within this invocation. A declared tool is not proof it is installed. Preserve the original human gates.\n\n' + duty + '\n';
  return Buffer.from((front + '\n---' + notice + body).replace(/\n/g, eol));
}

module.exports = { project, roles };

// Optional review export. Output must be a NEW directory, outside the repository.
if (require.main === module) {
  const output = process.argv[2];
  if (!output) throw new Error('Usage: node scripts/native-profile.js <new-output-directory>');
  const root = path.resolve(__dirname, '..');
  const dest = path.resolve(output);
  if (dest === root || dest.startsWith(root + path.sep) || fs.existsSync(dest)) {
    throw new Error('Choose a new output directory outside the repository.');
  }
  for (const dir of ['agents', 'prompts']) {
    fs.mkdirSync(path.join(dest, dir), { recursive: true });
    for (const name of fs.readdirSync(path.join(root, dir))) {
      const rel = `${dir}/${name}`;
      fs.writeFileSync(path.join(dest, rel), project(rel, fs.readFileSync(path.join(root, rel))));
    }
  }
  fs.mkdirSync(path.join(dest, 'docs/framework'), { recursive: true });
  fs.copyFileSync(path.join(root, 'docs/framework/native-al-tools.md'), path.join(dest, 'docs/framework/native-al-tools.md'));
  console.log(`Review export: ${dest} (agents/prompts and contract; use installer for a complete toolkit)`);
}
