# AL Spec Agent

AL Spec Agent turns approved Business Central requirements into technical contracts
before implementation. The `al-spec.create` entrypoint uses this same role.

For MEDIUM/HIGH work: Architect → Spec Agent → human approval → Conductor.
For LOW work: approved requirement → Spec Agent → human approval → Developer.

## Responsibilities

- Preserve approved architectural decisions and the assigned scope.
- Specify objects, data, procedures, events, permissions and acceptance criteria.
- Research ordinary technical questions using the target sources and symbols.
- Return material contradictions to Architect with the affected decision identified.
- Record the instructions and domain skills actually read, so work can resume from
  the current files and approved revisions.

MEDIUM specifications describe complete applicable contracts without AL implementation
bodies. HIGH adds detail where a concrete risk requires it. A verified event declaration
is not proof of execution order, persistence or runtime behavior.

## Review and implementation

Spec Agent writes its assigned `.spec.md`; it does not change AL, manifests,
approved architecture or shared memory. It does not compile, deploy or approve
its own work. A specification stays pending until the user approves its revision.
Conductor receives the approved specification and its remaining verification needs.

Use the [specification template](templates/spec-template.md) for the document
structure and [architecture template](templates/architecture-template.md) for design.
The role contract governs behavior; templates provide the structure.

## Distribution and compatibility

The canonical role is `agents/al-spec-agent.agent.md`. Foundation and the Claude,
Copilot CLI and Codex adapters are generated from the canonical sources. Relative
references are adapted to the installed host layout.

In Copilot Chat, prompt files require a session type that supports them. If the host
does not expose the prompt, use its supported direct custom-agent entrypoint and
verify discovery. Do not infer host loading from file presence. Doctor recognizes
legacy installations and reports a missing role linked by a newer entrypoint.
