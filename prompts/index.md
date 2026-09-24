# Agentic Workflows

**Complete execution processes** implemented as `.prompt.md` files providing **systematic workflows** for specific AL development tasks in Business Central.

## How to Use Workflows

Activate workflows explicitly when needed:
```
@workspace use al-initialize
@workspace use al-spec.create
@workspace use al-build
```

## Available Workflows (12 files)

### Environment & Setup

| Workflow | Purpose |
|----------|---------|
| [al-initialize](al-initialize.prompt.md) | Complete environment and workspace setup |
| [al-context.create](al-context.create.prompt.md) | Generate project context for AI assistants |
| [al-memory.create](al-memory.create.prompt.md) | Create session memory for continuity |

### Development & Delivery

| Workflow | Purpose |
|----------|---------|
| [al-spec.create](al-spec.create.prompt.md) | Functional-technical specification as an implementable blueprint |
| [al-build](al-build.prompt.md) | Build, package, and deploy extensions |
| [al-pr-prepare](al-pr-prepare.prompt.md) | Pull request draft with summary, testing notes, checklist |
| [al-doc-update.aproda](al-doc-update.aproda.prompt.md) 🟦 | Refresh per-module technical reference (EN) + handbook (de-CH) at the delivery boundary |

### BC Agents Pack

| Workflow | Purpose |
|----------|---------|
| [al-agent.create](al-agent.create.prompt.md) | End-to-end creation of a coded agent via the Agent SDK (7 phases) |
| [al-agent.task](al-agent.task.prompt.md) | AL code for Agent SDK task integration |
| [al-agent.instructions](al-agent.instructions.prompt.md) | Natural-language agent instructions (Responsibilities-Guidelines-Instructions) |
| [al-agent.build-instructions](al-agent.build-instructions.prompt.md) | Same framework, build-oriented variant |
| [al-agent.test](al-agent.test.prompt.md) | Test codeunits for Agent SDK integrations (6 categories) |

> 🟦 = Aproda layer (`.aproda.` infix). See [`decisions.aproda.md`](../.github/decisions.aproda.md) D-13 / D-14.

## Not workflows — these are skills

Debugging, events, pages, permissions, translation, migration, performance and Copilot features have **no**
`.prompt.md` workflow. They are [skills](../skills/index.md) that agents load on demand:

| You might look for | Use instead |
|--------------------|-------------|
| `al-diagnose` | `skill-debug` via `@AL Implementation Specialist` or `@AL Triage` |
| `al-events` | `skill-events` |
| `al-pages` | `skill-pages` |
| `al-permissions` | `skill-permissions` |
| `al-translate` | `skill-translate` |
| `al-migrate` | `skill-migrate` |
| `al-performance`, `al-performance.triage` | `skill-performance` |
| `al-copilot-*` | `skill-copilot` |

## Workflows vs Orchestra

- **Simple task** (1-2 files) → Use standalone workflow
- **Complex feature** (3+ objects, TDD needed) → Use `al-conductor`

## Learn More

- [Full Documentation](../docs/prompts/index.md)
- [Detailed Workflow Guide](README.md)
- [Getting Started](../docs/getting-started.md)

---

**Framework**: ALDC Core v1.2 · **Layer**: 1.2.0_aproda.17  
**Last Updated**: 2026-09-24
