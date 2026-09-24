# E-007 — Remediation Plan (V1)

> ⚠️ **Superseded as an implementation plan by [E-007-V2.md](E-007-V2.md)** (MCP-first hybrid
> architecture). Phase 2 and Phase 3 below (CLI-only tier model, 4 long scripts, single auth script) are
> **not** the target design anymore. **Still authoritative:** the Findings table in
> [README.md](README.md) (F-1…F-6) and Phase 1 (error-handling hardening) — both are referenced directly
> by V2, which retargets Phase 1's fixes at the new az-CLI building blocks instead of the original 4
> scripts. Phase 0 is done and stands regardless of V1/V2.
>
> **Nothing beyond F-1 (org URL) has been executed.** This is a proposal for maintainer approval.
> Phase 2 is a D-16 layer-policy change and needs an explicit maintainer decision + a `decisions.aproda.md`
> entry (D-48, drafted below) before any file changes.

---

## Phase 0 — Already done (F-1)

- All 4 scripts (`Get-AdoWorkItem.ps1`, `Get-AdoPullRequest.ps1`, `Create-AdoPullRequest.ps1`,
  `Update-AdoWorkItem.ps1`): `-Organization` changed from mandatory bare-name to optional, defaulting to
  `https://dev.azure.com/alphasol`.
- `SKILL.md`: Prerequisites section explains why (`az --organization` requires the fully qualified URL);
  the CLI-operations table and SRP-safe execution example no longer list `Organization` as a
  caller-supplied parameter.

No further action needed here unless Aproda ever operates a second ADO organization.

---

## Phase 1 — Error handling hardening (no policy change, safe to implement independently)

Applies to all 4 scripts in `skills/skill-aproda-ado/scripts/`.

### 1.1 Stop losing `$LASTEXITCODE` on validation-only failures

Every early `Write-Error; return` that happens **before** any `az` call (e.g. "SourceBranch/TargetBranch
must differ", "State or Comment required", "DescriptionFile empty") must set an explicit exit signal
first, so a caller checking `$LASTEXITCODE` right after `& $script ...` never reads a stale value left
over from an unrelated earlier command in the same session.

```powershell
if ($SourceBranch -eq $TargetBranch) {
    Write-Error "SourceBranch and TargetBranch must differ ('$SourceBranch')."
    $global:LASTEXITCODE = 1
    return
}
```

Apply the same pattern to every other pre-flight validation error, and set `$global:LASTEXITCODE = 0`
on every successful exit path.

### 1.2 Stop swallowing the real `az` error text

Every `2>$null` on a data-producing `az` call currently discards the actual CLI error (401/403/404,
network, bad org/project name, etc.) and replaces it with a generic "not reachable" message. Capture
stderr separately from stdout and fold the (trimmed) `az` error text into the `Write-Error` message:

```powershell
$stderr = [System.Collections.Generic.List[string]]::new()
$raw = az boards work-item show --id $WorkItemId --organization $Organization --output json --only-show-errors 2>&1 |
    ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $stderr.Add($_.ToString()); $null } else { $_ }
    }
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
    Write-Error "Failed to read work item $WorkItemId. az CLI said: $($stderr -join ' ')"
    return
}
```

Applies to: `az extension list` (all 4 scripts), and the main data call in each script (`work-item show`,
`pr show`, `pr list`, `pr create`, `work-item update`).

### 1.3 Wrap `ConvertFrom-Json` calls

If `az` ever returns non-JSON stdout (mixed warnings), `ConvertFrom-Json` throws an uncaught terminating
error today (raw PowerShell stack trace instead of a clean message). Wrap each call:

```powershell
try { $workItem = $raw | ConvertFrom-Json }
catch { Write-Error "az returned non-JSON output: $raw"; $global:LASTEXITCODE = 1; return }
```

### 1.4 Harden `Title` against the same class of risk already solved for multiline content

`Create-AdoPullRequest.ps1` neutralizes only `"` in `$Title` (`-replace '"', "'"`) before it reaches
`az.cmd` (which re-parses through `cmd.exe` on Windows). `Title` is untrusted input (agent-composed /
derived from ADO text) — the same `&`, `|`, `^`, `<`, `>` risk the script already solved for the
multiline description via the `@file` trick is unsolved for `Title`. Fix: pass `Title` the same way via
a temp file (`--title @<file>` is not supported by `az repos pr create`; confirm before implementing —
if unsupported, strip/reject the dangerous characters instead of just `"`).

### 1.5 Minor

- `Set-Content -Encoding utf8` → `-Encoding utf8NoBOM` where the PowerShell version supports it, to avoid
  a stray BOM landing in ADO comments/descriptions.

**Effort:** small, mechanical, no behavior change for the happy path. Recommended to do this regardless
of Phase 2's outcome.

---

## Phase 2 — 4-tier write model (D-16 policy change — needs sign-off first)

### Proposed decision: D-48 — Tiered write classification replaces the 2-command allowlist

Supersedes the original `skill-aproda-ado` "Forbidden" list (created under D-4). Every `az boards`/
`az repos`/`az pipelines`/`az devops` write command is classified into exactly one tier; **default for
anything not explicitly classified is Tier 3 (HITL-gate)**, not Tier 1 — except `az devops invoke`, which
stays hard-forbidden as a standalone carve-out (see rationale below). Reads are always allowed (Tier 4).

#### Tier 1 — Hard-forbidden (no HITL override, ever)

| Area | Command(s) |
|---|---|
| Branch/PR policies | `az repos policy create/update/delete` |
| Org/project settings | `az devops project create/update/delete`, `az devops team *` |
| Permissions | `az devops security permission update/reset/reset-all` |
| Repo lifecycle | `az repos create/delete/update` |
| Service connections | `az devops service-endpoint *` |
| Pipeline definitions + secrets | `az pipelines create/delete`, `az pipelines variable-group *` |
| Work item deletion | `az boards work-item delete` |
| PR policy bypass | `az repos pr update --bypass-policy true` (**only this flag** — see note) |
| Raw REST passthrough | `az devops invoke` — **standalone carve-out, not governed by the "default = Tier 3" rule**: `invoke` can call *any* ADO REST endpoint with no command-level classification possible, so if it fell under the generic "unlisted = HITL" default it would let one confirmation bypass every Tier-1 entry above. Must stay a hard, separate block regardless of how the general default evolves. |

> **Technical note on PR completion:** `az repos pr update --status completed` / `--auto-complete true`
> are **not separate commands** — they are parameters of the same `az repos pr update` used for ordinary
> title/description edits (Tier 3, below). A generic write-wrapper cannot block on command name alone
> for this one case; it must inspect the actual parameter values passed and only reject
> `--bypass-policy true`.

#### Tier 2 — Write "trusted" (routine ALDC flow; standard preview-and-approve gate, no extra ad-hoc HITL)

| Command | Agent-behavior constraint |
|---|---|
| `az repos pr create` | — |
| `az boards work-item update --discussion @file` (comment only, no `--state`) | Can be part of the routine flow (e.g. completion comment in `al-pr-prepare`) |
| `az boards work-item update --state ...` | **Optional, on-request only** — the agent must never call this as an automatic side effect of another flow; only when the user explicitly asks for a state change. Technically still gated by the script's existing `ShouldProcess`/preview-and-approve step. |
| `az repos pr reviewer add` | **Optional, on-request only** — same rule as state: never automatic, only when the user explicitly asks to add a reviewer. |

#### Tier 3 — Write "all other" (HITL-gate — explicit confirmation every single call, self-verified per D-35)

Everything not in Tier 1 or Tier 2, including (non-exhaustive, illustrative):
- `az pipelines run`
- `az repos pr update --status completed` / `--auto-complete true` (without `--bypass-policy`)
- `az repos pr update --title/--description/--draft`
- `az boards work-item create`
- `az boards work-item update --assigned-to/--area/--iteration/--tags`
- `az boards work-item relation add`

#### Tier 4 — Read (always allowed, no gate)

Any `show`/`list`/`query` subcommand under `az boards`, `az repos`, `az devops project`.

### Open questions still blocking implementation

1. **`az repos pr set-vote`** (Approve/Reject/Wait-for-author — the actual "PR review" action available
   via CLI; there is **no** `az repos pr comment` command at all, confirmed via MS Learn docs — PR
   thread/inline comments are web-portal-only) — Tier 2 (trusted, on-request only like State/Reviewer) or
   Tier 3 (HITL every time)? Not yet decided.
2. **`az repos pr update --description/--title`** — stays Tier 3, or promotes to Tier 2? Not yet decided.
3. Confirm whether `az repos pr create --title @file` (or equivalent) exists, to close Phase 1.4 the same
   way multiline descriptions are already handled; if not, decide the fallback sanitization approach for
   `Title`.

### Implementation shape once confirmed

- Two options were discussed for how to structure this in code (Phase 2 vs Phase 3 below are independent
  of each other):
  - **(a)** Keep today's shape: one script per operation, but reclassify what's exposed vs. blocked.
  - **(b)** Collapse into a generic read-wrapper + a generic write-wrapper, each carrying an internal
    per-subcommand/per-parameter tier table (needed for the `pr update` parameter-level check above
    regardless of (a) or (b)).
  - Recommendation from the design discussion: **(a) first** (lower risk, smaller diff), **(b) only if**
    the tier list keeps growing and duplication across per-operation scripts becomes painful.

---

## Phase 3 — Preflight/auth consolidation (optional, independent of Phase 2)

The `Get-Command az` + `az extension list` preflight block is duplicated verbatim across all 4 scripts.
Proposal: extract into a single `Test-AdoAuth.ps1` (or a dot-sourced helper), run once before any
read/write script executes. Also the natural place to add a proactive stale-token check (the
"Web works, CLI doesn't" pattern documented in the separate `ado-cli-access-diagnose` lessons-learned —
force `az logout`/`az account clear`/`az login` if the token looks stale) without touching the 4
operation scripts themselves.

**Effort:** small, no policy decision needed, safe to do independently of Phase 2's outcome.

---

## Suggested execution order

1. Phase 1 (error handling) — no sign-off blocker, do first.
2. Phase 3 (preflight consolidation) — no sign-off blocker, can run in parallel with/after Phase 1.
3. Phase 2 (tier model) — **blocked on the 3 open questions above** + explicit maintainer confirmation
   + the D-48 entry in `decisions.aproda.md`.
