#!/usr/bin/env node
'use strict';
// Complements the existing Claude source/mirror generator; does not rebuild roles.
const fs = require('fs');
const path = require('path');
const { walk, provenance, normalized } = require('./package-provenance');
const root = path.resolve(__dirname, '..');
function support(surface, rootDir = root) {
  const files = new Map();
  for (const rel of ['aldc_context_doctor.py', 'README.md']) {
    const dest = surface === 'codex' ? (rel.endsWith('.py') ? 'skills/aldc/scripts/' + rel : 'skills/aldc/references/doctor.md') : 'tools/context-doctor/' + rel;
    files.set(dest, fs.readFileSync(path.join(rootDir, 'tools/context-doctor', rel), 'utf8'));
  }
  if (surface === 'claude') for (const p of walk(rootDir, 'skills/skill-agent-instructions/examples')) files.set(p, fs.readFileSync(path.join(rootDir,p), 'utf8'));
  for (const name of ['install-transaction.js', 'package-provenance.js']) files.set(`scripts/${name}`, fs.readFileSync(path.join(rootDir,'scripts',name), 'utf8'));
  files.set('scripts/init.js', fs.readFileSync(path.join(rootDir, 'scripts/init-plugin.js'), 'utf8'));
  for (const p of walk(rootDir, 'docs/templates')) files.set(p, fs.readFileSync(path.join(rootDir,p), 'utf8'));
  files.set('templates/memory-template.md', fs.readFileSync(path.join(rootDir,'docs/templates/memory-template.md'), 'utf8'));
  files.set('surface.json', JSON.stringify({ surface }, null, 2) + '\n');
  files.set('project-guidance.md', surface === 'codex' ?
    'Use the ALDC skill at .agents/skills/aldc/SKILL.md for Business Central development. Read the relevant role, workflow and AL rules there before acting. Preserve approved plans and .github/plans/memory.md. Human gates and the current session authorization apply.\n' :
    `This project uses the ALDC ${surface === 'claude' ? 'Claude Code' : 'Copilot CLI'} plugin. Discover its installed agents/commands/skills and read their full contracts. Use al-architect for design, al-developer for implementation and al-conductor for TDD orchestration. Keep approved artifacts and memory in .github/plans/. Read the ${surface === 'claude' ? '.claude/rules' : '.github/instructions'} AL rules for the affected files. Host loading and tool availability must be observed; installation does not certify them. Preserve material human gates.\n`);
  files.set('project-guidance.md', files.get('project-guidance.md') +
    `At session start or after an environment change, run the read-only ALDC Doctor with an available Python 3.9+ interpreter. Use --workspace for this project and --host ${surface}; --toolkit names the installed plugin root (or this project for Codex local bootstrap). See ${surface === 'codex' ? '.agents/skills/aldc/references/doctor.md; script .agents/skills/aldc/scripts/aldc_context_doctor.py' : 'tools/context-doctor/README.md and aldc_context_doctor.py in the installed plugin'}. Repeat only affected --operation checks. File presence and exit 0 do not certify host loading or execution. Do not install an interpreter automatically.\n`);
  return files;
}
function sync(check = false) {
  const dest = path.join(root,'claude-plugin'), outputs = support('claude');
  for (const rel of walk(dest)) if (rel !== 'provenance.json' && !outputs.has(rel)) outputs.set(rel, normalized(fs.readFileSync(path.join(dest,rel))));
  const sources = [...outputs.keys()].filter(p => !support('claude').has(p)).map(p => 'claude-plugin/' + p);
  sources.push(...walk(root, 'tools/context-doctor'),'scripts/install-transaction.js','scripts/package-provenance.js','scripts/init-plugin.js',...walk(root, 'docs/templates'), ...walk(root, 'skills/skill-agent-instructions/examples'));
  outputs.set('provenance.json', provenance(root,sources,outputs,'scripts/sync-plugin-support.js'));
  let drift = 0;
  for (const [rel,b] of outputs) {
    const p = path.join(dest,rel);
    if (fs.existsSync(p) && normalized(fs.readFileSync(p)).equals(normalized(Buffer.from(b)))) continue;
    drift++; if (check) console.error(`drift: claude-plugin/${rel}`);
    else { fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,b); }
  }
  console.log(`Claude support/provenance: ${drift} differences`); return check && drift ? 1 : 0;
}
if (require.main === module) process.exitCode = sync(process.argv.includes('--check'));
module.exports = { support, sync };
