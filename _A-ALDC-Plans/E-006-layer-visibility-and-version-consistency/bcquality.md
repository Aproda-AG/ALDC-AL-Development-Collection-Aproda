# BCQuality — evidence, audits and the per-user clone path

> **Own chapter, split out of E-006 on 2026-09-24.** BCQuality surfaced as a side finding while closing
> Block 1 (F-16), but it is not a layer-visibility problem — it is its own subject with its own
> requirement, its own defects and its own decision. Keeping it inside
> [`findings-01`](findings-01-layer-visibility.md) would bury it.
>
> **Status until Block 4: leave everything as-is.** Nothing in this file has been changed. It is a
> notebook, not a change log. Everything below was observed during the Block-1 session — no separate
> research has been done yet, and several entries explicitly need it.

---

## 1. The requirement (user, 2026-09-24)

> *"Es soll zuverlässig pro user funktionieren. Jeder user kann sein BCQ clone an einem anderen Ort im
> Verhältnis zum Projekt-Repo haben. Workspace + aldc sind repo settings, also nicht optimal. Idee wäre,
> diesen Pfad zentral in den VS Code user settings zu führen. Muss stabil funktionieren."*

Restated: **the clone location is a property of the workstation, not of the repository.** Today it is
configured in two repo-scoped places (`aldc.yaml → external.bcquality.home`, `*.code-workspace`), which
forces every developer onto the same relative layout and makes the value wrong for anyone who deviates —
including the fork itself (see B-5). The target is a single, user-scoped, reliably resolved path.

**Not yet designed.** What follows is only what is already known from reading the code, not a solution.

### Resolution mechanisms that already exist

`validate_evidence.py` resolves the clone in this order (lines 81–115):

1. `--bcquality-root` (CLI argument)
2. `$BCQUALITY_HOME` (environment variable) — **already user-scoped**
3. `aldc.yaml → external.bcquality.home` (repo-scoped)

Then it confirms the clone by probing `skills/entry.md`.

So a user-scoped channel **exists at the script level**. Open question is what fills it, and whether the
same channel is honoured by the other consumers (agents/skills reading `entry.md`, the install scripts,
the multi-root workspace, the VS Code extension).

### Candidate directions (unresearched, listed to be checked — not chosen)

| Direction | Note |
|---|---|
| VS Code **user** setting read by the Aproda extension | `tools/aproda-vscode-extension/src/workspace/bcqualityRoot.ts` and `src/bcquality/install.ts` already exist and appear to own this concern — start here |
| `$BCQUALITY_HOME` as the canonical channel, set once per workstation | Already honoured by the validator; unclear whether agents/workspace honour it |
| `aldc.yaml` value demoted to a fallback/default | Would keep repos working without per-user setup |
| `site-profile.aproda.md` | Aproda-wide infra facts live here, but it is repo-scoped too — likely wrong layer |

**Reliability is the stated bar.** Whatever is chosen must fail *loudly* when the clone is missing —
today it fails silently (B-6), which is the worst possible behaviour for a verification tool.

---

## 2. Ownership — BCQuality is Upstream, not Aproda

Verified via `git log --diff-filter=A`:

```
fa37cf7  2026-06-05  Javier Armesto Gonzalez
feat: upstream FORGE innovations into ALDC (port + docs + distribution + plugin) (#51)
```

Present in the pinned ALDC base (`4f3371f`): `tools/bcquality/**`, `.github/workflows/bcquality-evidence.yaml`,
`docs/bcquality.md`. **Aproda's contribution is the fork URL**, not the mechanism.

Consequence: fixes here are candidates for an **upstream PR** (Block 5), not fork-local edits — with the
exception of the per-user path, which is an Aproda requirement and may well be one too.

---

## 3. How it is supposed to work

| Piece | Role | Runs where |
|---|---|---|
| `tools/bcquality/install.{sh,ps1}` | Clone BCQuality next to the repo | Human, once per workstation |
| BCQuality clone (`skills/entry.md`) | Citable knowledge; agents route through the entry point | Agent, at review time |
| `al-review-subagent`, `dredd` | Produce findings with `references[].path` | Agent |
| `al-conductor` | Persists the reports, reports the CI verdict | Agent |
| `validate_evidence.py` | Resolves **every** citation against the clone | CI |
| `.github/workflows/bcquality-evidence.yaml` | Runs the validator on PR | GitHub-hosted runner |

The division of labour is the whole point: **agents assert, CI falsifies.** That is exactly what
`copilot-instructions.md` calls the difference between *declarative* and *falsifiable* evidence.

Two artifact families feed the validator — both count as "audit checking" in this chapter:

- **Review evidence** — `.github/plans/**/*-review-phase-*.json` (superset) and `*-bcquality-*.json` (derived view)
- **Audit evidence** — `.github/audits/**/*-audit-*.json`, written by `@dredd`

---

## 4. Findings (all observed 2026-09-24, nothing fixed)

| # | Finding | Evidence |
|---|---|---|
| **B-1** | `neverTouchExceptions → workflows/bcquality-evidence.yaml` is **inert**. `.github/workflows/…` reverse-maps to `$null` before the exception is consulted, so the CI has never shipped to any project | = E-006 **F-16**; verified absent in `straub-medical-ag-base` |
| **B-2** | The manifest comment calls it *"our BCQuality evidence workflow"* — **false ownership**, it is Upstream's | `aproda-sync.json` lines 134–135 vs. §2 above |
| **B-3** | `aldc.yaml` lines 64–66 declare `validator:` and `ciWorkflow:` as machine-readable config. **Both files are absent in a consuming project**, and `aldc.yaml` ships as `dualVariant` — so the shipped config points at nothing | Reference project: `tools/bcquality/validate_evidence.py` and `.github/workflows/bcquality-evidence.yaml` both FEHLT |
| **B-4** | `copilot-instructions.md` line 127 promises CI validation *"A hallucinated citation or a drifted pin fails the check"*. In a project the whole apparatus is missing ⇒ the evidence chain is **purely declarative there**, i.e. precisely what that section rules out | Same measurement as B-3 |
| **B-5** | `external.bcquality.home: "../../BCQuality-Aproda"` resolves from the fork root to `C:\_EphemeralWorkspace\BCQuality-Aproda` — **does not exist**. The clone is one level up, at `…\Florian Köll\BCQuality-Aproda`. The validator therefore skips citation resolution **although a clone is present** | = **T-17**; reproduced live: run without `--bcquality-root` reported *"clone not available"*, run with the real path found it |
| **B-6** | **The validator reports PASSED when it has verified nothing.** Three independent paths to false green: no clone, wrong clone path (B-5), no evidence files. All three exited `0` | 3 local runs, each `BCQuality evidence validation PASSED (0 citation(s) across 0 file(s))`, exit 0 |
| **B-7** | **Check 1 (pin coherence) no longer exists.** The docstring claims a three-way cross-check (`aldc.yaml` + both install scripts, *"a drift in any of them fails the build"*); the code states `# there is no hardcoded pin to cross-check` and only prints a note. `copilot-instructions.md` still advertises the three-way check | `validate_evidence.py` docstring lines 6–10 vs. code line 101; `copilot-instructions.md` line 127 |
| **B-8** | `.github/audits/` does **not exist** in the fork (0 files), although it is a declared trigger path and Dredd's output location. Audit evidence has therefore never been exercised end-to-end | Directory listing during the Block-1 session |

### Cross-cutting

B-3, B-4 and B-7 are the same failure mode as E-006's T-9/T-19: **a documented or declared capability
that is not in effect.** Here it occurs three times within one subsystem, twice in shipped artifacts.
Whatever Block 4 decides, the honesty of the shipped documentation has to be restored — that part is
independent of whether the CI ever ships.

---

## 5. Open items

*Numbering continues E-006's. Nothing below is started.*

| # | Item | Depends on |
|---|---|---|
| **T-17** | Fix `external.bcquality.home` (B-5). **Moved into this chapter from Block 3** — it is not a path-layout nit, it silently disables citation checking | — |
| **T-21** | Decide B-1: make the declared exception work (`workflows/**` in `dotGithub` + `tools/bcquality/**`), or declare the CI fork-only and drop it from `neverTouchExceptions`. **Note:** the workflow clones `Aproda-AG/BCQuality-Aproda` unauthenticated — if that repo is private, the job fails on a GitHub runner. Verify before choosing option (a) | — |
| **T-22** | **Per-user clone path** (§1) — the actual requirement. Design first, then implement | — |
| **T-23** | Make the validator **fail loudly instead of passing vacuously** (B-6): distinguish "verified N citations" from "verified nothing". Prerequisite for any gate | — |
| **T-24** | Restore honesty in the shipped docs (B-3, B-4, B-7): `aldc.yaml` pointers, `copilot-instructions.md` line 127, the script docstring | — |
| **T-25** | Correct the false-ownership comment (B-2). One line, no dependencies | — |
| **T-26** | **Agent-executed gate in `al-pr-prepare`** — run the validator at the Completion Gate so hallucinated citations are caught *before* the PR, independent of whether the CI ever ships. Feasibility confirmed: Python 3.14.7, stdlib only, clean exit codes, runs over our umlaut path; the gate already has the pattern (*"HARD GATE — a verification step, not a checklist to narrate"*, line 173). **Must evaluate the `notes`, not the exit code** (B-6), and must be labelled a self-check: the agent that produced the citations is not an independent verifier | T-17, T-23 |
| **T-27** | Exercise audit evidence end-to-end (B-8) — does a Dredd run actually produce a validatable `*-audit-*.json`? | T-17 |

---

## 6. What holds until Block 4

- **Nothing is changed.** The CI stays fork-only, the paths stay as they are, the docs keep their claims.
- BCQuality-backed reviews keep working where a clone happens to be mounted — the knowledge base itself
  is unaffected by all of the above. **Only the verification layer is broken, not the knowledge layer.**
- Consequence to be aware of meanwhile: any BCQuality citation produced in a project is **unverified**.
  Treat "BCQuality Evidence" blocks in phase reports as claims, not as proof.
