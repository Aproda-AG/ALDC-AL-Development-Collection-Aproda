# E-009 — Prompt files are deprecated: migrate the 12 workflows to agent skills

> **Status: open, not started.** Opened 2026-09-29 from a side-finding while auditing
> `al-spec.create.prompt.md`. Nothing is broken today — this is a deadline, not a defect.

## The finding

Microsoft's own documentation, [Use prompt files in VS Code](https://code.visualstudio.com/docs/copilot/customization/prompt-files)
(page edited 2026-09-16), states verbatim:

> **Prompt files are deprecated for Agent Host sessions and aren't loaded by Agent Host.** They continue
> to work with the Local agent for now, but the Local agent will be removed in a future release. Use
> prompt file migration to convert existing prompts to agent skills. **This experimental migration is
> enabled by default.**

ALDC ships **12 workflows, all of them prompt files** (`prompts/*.prompt.md`, registered in
`aldc.yaml → required.workflows` + `optional.workflows`). They are one of the framework's four
primitive types and are named as such in `copilot-instructions.md`, `agents/index.md`,
`prompts/index.md` and `prompts/README.md`.

## Why this matters more than it looks

The deprecation is **not** about the files being wrong. It is about the runtime that loads them being
scheduled for removal. Three consequences, in order of how quietly they would arrive:

1. **Agent Host sessions already ignore them.** Any user or CI path running under Agent Host gets *no*
   workflow — no error, no warning, the slash command simply is not there. Same shape as the tool-name
   failures in E-006 (`al_symbolrelations`, `al_get_diagnostics`): silent absence, not a loud failure.
2. **The migration is experimental and on by default.** So the conversion may already be happening on
   some machines, producing skills we have neither reviewed nor registered in `aldc.yaml`. Whatever the
   migration produces is not automatically *our* artifact.
3. **Skills and prompts are not interchangeable primitives in ALDC.** Prompts are invoked explicitly by
   a human (`@workspace use al-spec.create`) and carry `tools:`, `model:` and `agent:` frontmatter.
   Skills are loaded on demand by an agent and carry none of that. A naive 1:1 conversion loses the
   model pinning and the tool grants — and for `al-spec.create` the tool grant *is* the contract
   (symbol verification of every base-app event).

## Open questions (decide before any conversion)

| # | Question |
|---|---|
| 1 | Which of the 12 workflows are genuinely human-invoked entry points (keep that shape) and which are really domain knowledge an agent should load (true skill candidates)? |
| 2 | What replaces `model:` pinning? Today `al-spec.create` pins a model deliberately; a skill cannot. |
| 3 | What replaces `tools:`? A skill inherits the calling agent's grants — which for `al-spec.create` invoked under the Conductor would be the *wrong* set (see the tool-priority rule below). |
| 4 | Do we let the built-in experimental migration run, or convert deliberately and disable it? Letting it run produces artifacts outside `aldc.yaml`'s catalog. |
| 5 | Timeline: "will be removed in a future release" is not a date. Is there a version announcement to track? |

## Measured context (not assumptions)

- **Tool priority when a prompt runs** — from the same doc: *tools specified in the prompt file* win over
  *tools of the referenced custom agent* over *default tools of the selected agent*. So invoking
  `/al-spec.create` while `@AL Development Conductor` is selected runs with the **prompt's** tools, and
  `agent: agent` in that file switches away from the Conductor entirely.
- **Unavailable tools fail silently** — *"If a given tool is not available when running the prompt, it is
  ignored."* This is why a converted-but-under-granted skill would degrade invisibly rather than error.

## Scope boundary

This epic is about the **format and its runtime**, not about improving individual workflows. Content
changes to a workflow belong to whichever epic owns that workflow.
