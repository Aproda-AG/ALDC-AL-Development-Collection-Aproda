# ALDC Skills Catalog

## What are Skills?

Skills are composable knowledge modules in markdown format that agents load on demand based on task context. They encapsulate domain-specific patterns, workflows, and best practices.

Skills follow the GitHub Copilot Agent Skills structure (`skills/{skill-name}/SKILL.md`). Copilot auto-loads skills based on their `description` frontmatter — agents no longer need `@file` references.

## Required Skills (MUST exist)

| Skill | Domain | Loaded by |
|-------|--------|-----------|
| [skill-api](skill-api/SKILL.md) | API design, OData/REST, versioning | architect, developer |
| [skill-copilot](skill-copilot/SKILL.md) | Copilot capability lifecycle | architect, developer |
| [skill-debug](skill-debug/SKILL.md) | Debugging, profiling, root cause | developer |
| [skill-performance](skill-performance/SKILL.md) | Performance patterns, triage | architect, developer |
| [skill-events](skill-events/SKILL.md) | Event subscriber/publisher patterns | architect, developer |
| [skill-permissions](skill-permissions/SKILL.md) | Permission sets, security | developer |
| [skill-testing](skill-testing/SKILL.md) | Test strategy, Given/When/Then | conductor, developer |

## Recommended Skills (SHOULD exist)

| Skill | Domain | Loaded by |
|-------|--------|-----------|
| [skill-migrate](skill-migrate/SKILL.md) | Version migration, breaking changes | developer |
| [skill-pages](skill-pages/SKILL.md) | Page types, UX patterns | developer |
| [skill-translate](skill-translate/SKILL.md) | XLF, multi-language | developer |
| [skill-estimation](skill-estimation/SKILL.md) | Project estimation, SWOT | presales |
| [skill-manifest](skill-manifest/SKILL.md) | Extension handoff manifest for CIRCE/DELFOS at pipeline end | conductor (final phase) |

## BC Agents Pack Skills (3)

For building Business Central agents (Agent SDK / Designer), not the extension itself:

| Skill | Domain | Loaded by |
|-------|--------|-----------|
| [skill-agent-toolkit](skill-agent-toolkit/SKILL.md) | Agent SDK/Designer architecture, interfaces (`IAgentFactory`, `IAgentMetadata`, `IAgentTaskExecution`), naming conventions | al-agent-builder, architect |
| [skill-agent-task-patterns](skill-agent-task-patterns/SKILL.md) | Agent Task Builder, task lifecycle, 8 SDK integration patterns | al-agent-builder, architect |
| [skill-agent-instructions](skill-agent-instructions/SKILL.md) | Authoring/reviewing agent instructions (Responsibilities-Guidelines-Instructions framework) | al-agent-builder |

## Aproda Layer Skills 🟦 (5)

The `.aproda.` fork customization on top of ALDC Core. See [`../readme.aproda.md`](../readme.aproda.md) + [`../decisions.aproda.md`](../decisions.aproda.md). **Adding/removing one of these is itself an ALDC-layer extension** — see [skill-aproda-aldc](skill-aproda-aldc/SKILL.md) → Step 2.5 before you touch this table.

| Skill | Domain | Loaded by |
|-------|--------|-----------|
| [skill-aproda-aldc](skill-aproda-aldc/SKILL.md) | Explain/extend the Aproda ALDC layer itself; entry to `site-profile.aproda.md` | any (meta) |
| [skill-aproda-aldc-release](skill-aproda-aldc-release/SKILL.md) | Prepare/release the Aproda layer or VS Code extension (fork-maintainer only) | fork maintainer only |
| [skill-aproda-deploy-run-verify](skill-aproda-deploy-run-verify/SKILL.md) | OnPrem Deploy-Run-Verify Cycle (build→deploy→run→review) | developer, conductor |
| [skill-aproda-ado](skill-aproda-ado/SKILL.md) | ADO work-item conventions, `req_name` derivation, controlled `az` CLI ops | conductor, architect, triage |
| [skill-aproda-fkh](skill-aproda-fkh/SKILL.md) | Fkh transport/target resolution for OnPrem BC containers | skill-aproda-deploy-run-verify |


## Creating New Skills

1. Create folder `skills/skill-{domain}/`
2. Copy `docs/templates/skill-template.md` to `skills/skill-{domain}/SKILL.md`
3. Fill in all sections (including frontmatter with `name` and `description`)
4. Keep under 500 lines (context window optimization)
5. **Update the catalogs** — add the skill to this file (`skills/index.md`) and to `.github/copilot-instructions.md` → Skills table (mark 🟦 if it's an Aproda `skill-aproda-*` addition). See [skill-aproda-aldc](skill-aproda-aldc/SKILL.md) → Step 2.5 for the full list of catalogs that must stay in sync — this step has been missed repeatedly in practice and is not optional.
6. Submit PR (required skills need RFC approval)
