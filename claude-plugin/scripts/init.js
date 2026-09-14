#!/usr/bin/env node
'use strict';
// Canonical adaptation of Lab init.mjs and Codex install_runtime.py (b2ce9d9...).
// Distributed with the same transaction engine as Chat. Default is a dry run.
const fs = require('fs');
const path = require('path');
const tx = require('./install-transaction');
const { verify, walk, normalized } = require('./package-provenance');
function initialize({ project, pluginRoot, apply = false, force = false, rollback = false, check = false }) {
  project = path.resolve(project); pluginRoot = path.resolve(pluginRoot);
  if (project === pluginRoot || project.startsWith(pluginRoot + path.sep) || pluginRoot.startsWith(project + path.sep)) throw Error('Choose a project outside the plugin source tree');
  const surface = JSON.parse(fs.readFileSync(path.join(pluginRoot, 'surface.json'), 'utf8')).surface;
  if (!['claude', 'cli', 'codex'].includes(surface)) throw Error('Unsupported plugin surface');
  if (rollback) return tx.rollback(project, surface);
  if (check) return { drift: tx.drift(project, surface), hostLoading: 'unverified' };
  verify(pluginRoot); // Check all locked payloads before planning a project write.
  const files = new Map();
  const put = (rel, content, opts = {}) => {
    if (files.has(rel)) throw Error(`Duplicate destination: ${rel}`);
    files.set(rel, { content, ...opts });
  };
  const copy = (src, dst, opts) => put(dst, normalized(fs.readFileSync(path.join(pluginRoot, src))), opts);
  const ruleDest = surface === 'claude' ? '.claude/rules' : surface === 'cli' ? '.github/instructions' : '.agents/skills/aldc/references/rules';
  if (surface !== 'codex') for (const rel of walk(pluginRoot, 'rules-templates')) copy(rel, `${ruleDest}/${path.basename(rel)}`);
  copy('templates/memory-template.md', '.github/plans/memory.md', { seed: true });
  if (surface === 'codex') {
    for (const rel of walk(pluginRoot, 'skills')) copy(rel, '.agents/' + rel);
    for (const rel of walk(pluginRoot, 'agents')) copy(rel, '.codex/' + rel);
  }
  let guidance = surface === 'claude' ? 'CLAUDE.md' : 'AGENTS.md';
  if (surface !== 'claude' && tx.read(project, 'AGENTS.override.md') !== null) guidance = 'AGENTS.override.md';
  const before = tx.read(project, guidance);
  const fragment = fs.readFileSync(path.join(pluginRoot, 'project-guidance.md'), 'utf8');
  // Only the ALDC block is managed; preserve surrounding text, including CRLF.
  put(guidance, tx.managedBlock(before, fragment, surface.toUpperCase()), { retain: true, merge: before === null || !before.toString('utf8').includes(`<!-- BEGIN ALDC ${surface.toUpperCase()} -->`) });
  const result = tx.apply({ root: project, surface, files, force, dryRun: !apply });
  return { ...result, surface, guidance, hostLoading: 'unverified',
    note: 'Review collisions. Restart the host and inspect loaded sources; do not combine a Codex plugin install with its local bootstrap copies.' };
}
if (require.main === module) {
  try {
    const opts = { project: process.cwd(), pluginRoot: path.resolve(__dirname, '..') };
    const args = process.argv.slice(2);
    for (let i=0; i<args.length; i++) {
      const arg = args[i];
      if (arg === '--project' && args[i+1]) opts.project = args[++i];
      else if (arg === '--apply') opts.apply = true;
      else if (arg === '--force') opts.force = true;
      else if (arg === '--rollback') opts.rollback = true;
      else if (arg === '--verify') opts.check = true;
      else throw Error(`Unknown or incomplete argument: ${arg}`);
    }
    const result = initialize(opts); console.log(JSON.stringify(result, null, 2));
    if (result.drift?.length || result.files?.some(f => f.action === 'collision')) process.exitCode = 2;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { initialize };
