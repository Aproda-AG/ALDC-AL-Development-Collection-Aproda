# GitHub Copilot Instructions for AL Development

<!-- Workspace-specific custom instructions for Copilot. Reference: https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

## Overview

This workspace contains AL (Application Language) code for Microsoft Dynamics 365 Business Central. It uses the **ALDC Core v1.2** skills-based architecture, extended by the Aproda `.aproda.` layer (rows marked 🟦 below): **11 agents (7 user-facing + 4 internal subagents) + 21 skills + 12 workflows + 10 instructions**.

## Core Principles

These principles apply to ALL work in this repository:

- **Extension-only development** — Never modify base application objects. Use tableextensions, pageextensions, event subscribers.
- **Human-in-the-Loop (HITL)** — All critical decisions require user confirmation before proceeding.
- **TDD / spec-driven** — Features follow the flow: `spec.create → architecture → test-plan → implementation → review`.
- **Least privilege** — Generate only the minimum permissions required. Use XLIFF for all user-facing strings.
- **Output language: English** — All persisted artifacts under `.github/plans/**` (architecture.md, spec.md, plan.md, phase-N-complete.md, plan-complete.md, test-plan.md, delivery.md, review reports, Dredd audit reports, BCQuality findings JSON) MUST be written in English regardless of the chat conversation language. Inline chat responses MAY follow the user's language; persisted artifacts stay in English.
- **No named agent, same gates** — Even without an explicit `@`-agent: AL changes and ADO/PR actions follow the same HITL gates as `al-conductor`/`al-developer` (delivery-boundary `memory.md` updates) and `skill-aproda-ado` (explicit approval before any Tier-2/3 ADO write on either backend, never suppress the mandatory AI disclaimer).
- **Aproda layer edits are guarded (D-16)** 🟦 — Before changing any `.aproda.*` file or anything under `skill-aproda-*/`: name the governing decision in `.github/decisions.aproda.md`, state whether the change *relaxes* it, and get explicit confirmation. **In the aproda-aldc fork this guardrail does not auto-apply** — its `applyTo` cannot fire there (the toolkit sits at the repo root, not under `.github/`), so apply `instructions/aproda-aldc-steward.aproda.instructions.md` manually. In a consumer project it fires normally and this line is a reminder, not a substitute.

## Agent Routing

Choose the right agent for your task:

| Intent | Agent | What it does |
|--------|-------|-------------|
| Designing, analyzing architecture, strategic decisions? | `@AL Architecture & Design Specialist` | Solution design, data modeling, integration strategy |
| Implementing, coding, debugging, fixing? | `@AL Implementation Specialist` | Tactical implementation with full AL MCP tools |
| Building a feature with TDD orchestration (plan → implement → review → commit)? | `@AL Development Conductor` | Orchestrates planning, implementation, and review subagents |
| Estimating a project, sizing, proposals? | `@AL Pre-Sales & Project Estimation Specialist` | PERT estimation, SWOT analysis, cost breakdown |
| Diagnosing an existing bug/regression from a symptom? | `@AL Triage` | Reproduce, localize, root-cause; hands the fix to `@AL Implementation Specialist` |
| Auditing code independently against BCQuality (changes vs main, or all)? | `@Dredd` | Independent read-only auditor; advisory verdict with citations |
| Building/configuring a BC agent (Designer or Agent SDK)? | `@AL Agent Builder` | Agent Toolkit Builder — Designer + SDK paths |

### Quick routing guide

```
New feature (MEDIUM/HIGH)?      → @AL Architecture & Design Specialist → al-spec.create → @AL Development Conductor
New feature (LOW)?              → al-spec.create → @AL Implementation Specialist
Bug fix / debugging?            → @AL Implementation Specialist
Bug from a symptom (reactive)?  → @AL Triage → @AL Implementation Specialist
Architecture review?            → @AL Architecture & Design Specialist
Independent quality audit?      → @Dredd
Full TDD cycle?                 → @AL Development Conductor
Project estimation?             → @AL Pre-Sales & Project Estimation Specialist
Build a BC agent (SDK/Designer)? → @AL Agent Builder
```

## Workflows

6 workflows available via `@workspace use [name]`:

| Workflow | When to use |
|----------|-------------|
| `al-spec.create` | Create functional-technical specifications before development |
| `al-build` | Build, package, and deploy extensions |
| `al-pr-prepare` | Prepare pull requests with documentation and validation |
| `al-memory.create` | Generate/update memory.md for session continuity |
| `al-context.create` | Generate project context.md for AI assistants |
| `al-initialize` | Complete environment and workspace setup |
| `al-doc-update` 🟦 | Refresh per-module technical reference (EN) + de-CH handbook after delivery (Aproda D-14) |

> 5 additional BC Agents Pack workflows (`al-agent.create`, `al-agent.task`, `al-agent.instructions`, `al-agent.test`, `al-agent.build-instructions`) are documented in `docs/copilot-reference.md` → BC Agents Pack.

### Usage

```
@workspace use al-spec.create    # Create specification
@workspace use al-build          # Build & deploy
@workspace use al-pr-prepare     # Prepare PR
@workspace use al-initialize     # Setup project
```

## Skills

11 composable knowledge modules loaded on-demand by agents. You don't invoke skills directly — agents load them automatically when the task requires domain-specific knowledge.

| Skill | Domain | Loaded by |
|-------|--------|-----------|
| `skill-debug` | Debugging, diagnosis, snapshot debugging | al-developer |
| `skill-api` | API pages, OData, REST endpoints | al-developer, al-architect |
| `skill-copilot` | AI features, PromptDialog, AI Test Toolkit | al-developer, al-architect |
| `skill-events` | Event subscribers, publishers, handled pattern | al-developer, al-architect |
| `skill-permissions` | Permission sets, XLIFF, security | al-developer |
| `skill-pages` | Page types, FastTabs, actions, dynamic UI | al-developer |
| `skill-migrate` | BC version migration, upgrade codeunits, rollback | al-developer |
| `skill-translate` | XLF translation, NAB AL Tools, quality review | al-developer |
| `skill-performance` | CPU profiling, FlowField optimization, set-based ops | al-developer, al-architect |
| `skill-testing` | TDD, test strategy, AL Test Toolkit | al-architect, al-conductor |
| `skill-estimation` | PERT estimation, complexity scoring, SWOT | al-presales |
| `skill-manifest` | Extension handoff manifest for CIRCE/DELFOS at pipeline end | al-conductor (final phase) |
| `skill-aproda-deploy-run-verify` 🟦 | OnPrem Deploy-Run-Verify Cycle (build→deploy→run→review) | al-developer, al-conductor |
| `skill-aproda-aldc` 🟦 | Explain & extend the Aproda ALDC layer itself; entry to `site-profile.aproda.md` (infra) | any (meta) |
| `skill-aproda-ado` 🟦 | ADO work-item conventions, `req_name` derivation, controlled `az` CLI ops (PR/work-item create) | al-conductor, al-architect, al-triage |
| `skill-aproda-fkh` 🟦 | Fkh transport/target resolution for OnPrem BC containers | skill-aproda-deploy-run-verify |
| `skill-aproda-aldc-release` 🟦 | Prepare/release the Aproda ALDC layer or VS Code extension | fork maintainer only — never syncs to consumer projects |

> 🟦 = Aproda custom layer (`.aproda.` convention, 5 skills total). See [`readme.aproda.md`](readme.aproda.md) + [`decisions.aproda.md`](decisions.aproda.md). Remaining 4 skills (`skill-agent-instructions`, `skill-agent-task-patterns`, `skill-agent-toolkit`, `skill-contribution-assistant`) are BC Agents Pack / meta skills — see `docs/copilot-reference.md` → BC Agents Pack.

## External Knowledge: BCQuality

[BCQuality](https://github.com/microsoft/BCQuality) — a curated, citable knowledge base of Business Central guidance (atomic knowledge files + review skills) — is consumed from **outside the AL project**, reached through the tracked `.external/` wrapper (never mounted directly: a workspace root cannot exclude itself from search). Source/version is configurable in `aldc.yaml → external.bcquality` (defaults to upstream; point it at your own fork). See [`docs/bcquality.md`](../docs/bcquality.md) for install + usage.

> **Authoritative configuration:** When ALDC configuration affects a decision, invoke `#aldcConfiguration` (Aproda ALDC extension) before reading or inferring configuration. It resolves the Git root and returns root-level `aldc.yaml`, including `toolkitRoot`, plans, layer version, and BCQuality values, even when the repository root is not a workspace folder.
>
> **Reaching BCQuality — dual path.** Primary: the `#bcquality` tool (`read`/`list` against the resolver's verified clone). Fallback, in order: `#aldcConfiguration` for the resolved `home`, then `read_file <toolkitRoot>/aldc.yaml` for the declared static default — probe `<home>/<entryPoint>` before trusting it, never assume. Handle any non-configured result explicitly and never guess configuration values.

BCQuality is a **citation/audit layer, not a replacement** for the 7 auto-applied instructions or the 11 skills. The **AL Code Review Subagent** consults it (its "Step 0") before the A-G checklist: it routes via the BCQuality entry point (`<home>/skills/entry.md`, per `aldc.yaml`), runs the dispatched review skills, and folds the resulting findings — each backed by a knowledge-file citation — into the review report. A BCQuality `blocker`/`major` raises the review verdict like a native CRITICAL/MAJOR.

> **Pilot scope**: only `al-performance-review`, `al-security-review`, and `al-style-review` are enabled. Install the clone via the Aproda VS Code extension (*Aproda ALDC: Install / Update BCQuality*), which also creates the `.external/bcquality` link; `Aproda ALDC: Show BCQuality Status` shows where it resolved from.

## Skills Evidencing

Agents MUST declare which skills they loaded and which patterns they applied:

- **al-architect** → `> **Skills applied**: skill-api, skill-events` at top of architecture.md
- **al-developer** → `> **Skills loaded**: skill-debug (root cause analysis)` at start of response
- **AL Implementation Subagent** → `### Skills Loaded` section in Phase Summary returned to Conductor
- **AL Code Review Subagent** → returns a single `### Review-Report (JSON)` (its only output; read-only, cannot persist) carrying findings, verdict, and `review.skills-compliance`
- **al-conductor** → gates on the JSON, **renders** the human review from it (light checkpoint + full `code-review-template.md` in phase-complete.md), and persists the BCQuality leaf reports (from the JSON `sub-results`) to `.github/plans/<plan>/<plan>-bcquality-phase-<N>.json`; fills `Skills Applied`/`Skills Utilization` + the `BCQuality Evidence` block (phase) and roll-up (plan)

This traceability chain ensures every skill application is auditable end-to-end.

### BCQuality evidence: declarative vs falsifiable

The chain above is **declarative** — an agent could in principle claim a BCQuality consultation it did not perform. Two mechanisms make it **falsifiable**:

1. **Persisted findings-report** — the raw JSON on disk (`*-bcquality-phase-<N>.json`) carries each finding's `references[].path` (the cited knowledge file) and the pinned BCQuality SHA.
2. **CI validation — fork/CI only, not in a consuming project.** In this fork's CI the `bcquality-evidence` workflow runs `tools/bcquality/validate_evidence.py`, which verifies **every** citation resolves to a real file in the BCQuality clone (cloned via `--bcquality-root`); a hallucinated citation fails the check. Neither the validator nor the workflow ships to a consuming project (`tools/bcquality/**` and `.github/workflows/bcquality-evidence.yaml` are both absent there) — there, mechanism 2 does not exist, and the evidence chain is exactly as declarative as the opening sentence of this section describes. Tracked as E-006 T-21/T-23 (deferred to Block 5).

## Auto-Applied Instructions

Each instruction loads automatically when the file you're editing matches its `applyTo` glob. There is no semantic activation — only glob matching. The framework ships **10 instructions** (8 core + 2 Aproda 🟦). Narrow globs are deliberate: editing a Table or Page no longer drags codeunit-only rules into the prompt.

| File | `applyTo` | What it enforces |
|------|-----------|------------------|
| `al-guidelines.instructions.md`         | `**/*.al`                              | Core principles (event-driven, App focus, Test separation, naming as infrastructure) |
| `al-code-style.instructions.md`         | `**/*.al`                              | 2-space indent, PascalCase, feature-based folders |
| `al-naming-conventions.instructions.md` | `**/*.al`                              | 26-char object name limit, `<ObjectName>.<ObjectType>.al` file pattern, `I`/`Impl` for interfaces |
| `al-performance.instructions.md`        | `**/*.Codeunit.al`, `**/*.Query.al`    | SetRange/SetLoadFields before Find, CalcSums, no DB-calls in loops |
| `al-error-handling.instructions.md`     | `**/*.Codeunit.al`                     | TryFunctions, mandatory `Label`, telemetry only when explicitly requested |
| `al-events.instructions.md`             | `**/*.Codeunit.al`                     | Never modify base objects, subscribers `local` with exact signature, no `Commit` in subscribers |
| `al-testing.instructions.md`            | `**/test/**/*.al`                      | Tests only when asked, Given/When/Then, standard libraries |
| `al-agent-toolkit.instructions.md`      | `**/*Factory.Codeunit.al`, `**/*Metadata.Codeunit.al`, `**/*TaskExecution.Codeunit.al`, `**/*Setup.Codeunit.al` | Non-negotiable rules for AI Development Toolkit / Agent SDK code |
| `hitl-validation.aproda.instructions.md` 🟦 | `**/*.al`                           | Aproda D-11: HITL Validation lifecycle, `memory.md` Status contract |
| `aproda-aldc-steward.aproda.instructions.md` 🟦 | `**/*.aproda.*`, `**/skill-aproda-*/**` | Aproda D-16: HITL guardrail before editing the Aproda layer itself |

> `copilot-instructions.md` and `instructions/index.md` are **not** instructions in this sense — they have no `applyTo`. `copilot-instructions.md` is the always-on entrypoint; `index.md` is documentation.

> **Naming is infrastructure**: a file that doesn't follow `<ObjectName>.<ObjectType>.al` won't match the type-specific globs and will silently miss its instructions. `aldc-validate` checks the convention.

## Plans

Requirement sets live in `.github/plans/`, one subdirectory per requirement:

```
.github/plans/
├── memory.md                              # Global memory (decisions, context across sessions)
└── {req_name}/                            # One directory per requirement
    ├── {req_name}.spec.md                 # Functional-technical specification
    ├── {req_name}.architecture.md         # Architecture decisions
    ├── {req_name}.test-plan.md            # Test plan with acceptance criteria
    ├── {req_name}-phase-<N>-complete.md   # Phase completion reports (conductor)
    └── {req_name}-complete.md             # Final completion report (conductor)
```

> `memory.md` is GLOBAL and lives directly in `.github/plans/` (not in a subdirectory).

### Workflow with plans

**MEDIUM / HIGH:**

1. `@AL Architecture & Design Specialist` — Designs solution, creates `.github/plans/{req_name}/{req_name}.architecture.md`
2. `@workspace use al-spec.create` — Reads architecture, generates `.github/plans/{req_name}/{req_name}.spec.md` (detailed blueprint: object IDs, procedure signatures, AL code)
3. `@AL Development Conductor` — Reads spec + architecture from `.github/plans/{req_name}/`, orchestrates TDD: planning → implementation → review
4. `@workspace use al-pr-prepare` — Prepares PR referencing the plan

**LOW:**

1. `@workspace use al-spec.create` — Generates `.github/plans/{req_name}/{req_name}.spec.md` directly from codebase
2. `@AL Implementation Specialist` — Implements directly using spec as blueprint

## Complexity-Based Tool Selection

When a user provides requirements, assess complexity to route correctly:

**LOW** — Limited scope, single phase, no integrations
→ `al-spec.create` → `@AL Implementation Specialist` direct implementation

**MEDIUM** — 2-3 functional areas, internal integrations, conditional logic
→ `@AL Architecture & Design Specialist` → `al-spec.create` → `@AL Development Conductor` TDD orchestration

**HIGH** — Enterprise scope, 4+ phases, external integrations, complex workflows
→ `@AL Architecture & Design Specialist` design first → `al-spec.create` → `@AL Development Conductor` implement

Present the assessment and wait for user confirmation before proceeding.

## Further Reference

Human-facing reference material — examples, workspace layout, links, troubleshooting — lives in
`docs/copilot-reference.md` to keep this entrypoint lean (it is injected on every request). Path note
(T-14, E-006 F-11): that file sits next to this one — `../docs/copilot-reference.md` from here in this
fork (`docs/` at repo root), `./docs/copilot-reference.md` in a consuming project (`docs/` under
`.github/` there too) — a single relative link cannot resolve in both, so it is written in prose. It covers:

- **Code Generation Examples** — table + event-subscriber snippets with the auto-applied instructions each triggers
- **Best Practices for Copilot Interaction** — how to prompt, when to use agents vs workflows
- **Workspace Structure** — full directory tree of the ALDC framework
- **AL/BC Tools & MCP Servers** — Tier 1/2 tool reference, official vs. community MCP servers, known environment caveats (e.g. `al-symbols-mcp` availability, AppLocker/SRP)
- **BC Agents Pack (Extension)** — AI Development Toolkit agents/skills/workflows
- **Reference Documentation** — Microsoft + project doc links
- **Troubleshooting Copilot**

---

**Framework**: ALDC Core v1.2 (Skills-Based Architecture, Aproda-extended)
**Version**: 1.1.0
**Last Updated**: 2026-09-22
**Workspace**: AL Development for Business Central
**Primitives**: 11 agents (7 user-facing + 4 internal subagents) + 21 skills (5 🟦 Aproda) + 12 workflows (1 🟦 Aproda) + 10 instructions (2 🟦 Aproda)
