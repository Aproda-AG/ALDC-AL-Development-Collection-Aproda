# Run 4 — first init: a repository that has never seen ALDC (`HEKS Base`)

> **Read [`e2e-00-briefing.md`](e2e-00-briefing.md) first** — environment facts, hard rules, and §5
> (the user-settings reset). **Run this only after Run 3 has passed.**

**Purpose.** Everything Block 4 has been measured on so far was a *migration* — a project that already
carried the layer and was moved onto the new shape. `HEKS Base` carries nothing. This is the first time
the **first-init** path runs against a real repository.

That path matters more than a third migration sample, for one specific reason: **the B-23 fix changed
it, and the first repair attempt broke it silently.** The fallback must re-probe *after* the bootstrap,
because the bootstrap is what writes `aldc.yaml` in the first place. A single pre-bootstrap snapshot
made that lookup return nothing, and reconciliation was skipped without a word. It is covered by a
regression test verified to fail without the fix — but never by a real run.

---

## The starting state — measured 2026-09-26, do not re-derive

```
HEKS Base/
├── .git/                 branch: temp-fko-01
├── .gitignore            no "Aproda ALDC Tool" block
├── app.code-workspace    folders: source, test   ← the repo root is NOT a workspace folder
├── apr-go/
├── source/
└── test/
```

`.github/` — **absent**. `aldc.yaml` — **absent**. `.external/` — **absent**.

Two properties of this repo make it a better test than Straub, and both should be reported on
explicitly:

1. **The repository root is not a workspace folder.** Only `source` and `test` are mounted. This is
   exactly the condition behind **B-10** — `read_file aldc.yaml` at the root cannot work — so the repo
   resolution and `#aldcConfiguration` are load-bearing here, not convenient.
2. **`app.code-workspace` is not strict JSON.** Its `search.exclude` block ends with a **trailing
   comma**. Record the file verbatim before anything touches it; whether the rewrite survives that is a
   real question, not a formality.

---

## Phase 0 — Safety and baseline

The maintainer has confirmed the repo is reset and backed up, on throwaway branch `temp-fko-01`.

```powershell
$h = 'C:\_EphemeralWorkspace\Florian Köll\HEKS Base'
git -C $h status --short          # expect: clean
git -C $h branch --show-current   # expect: temp-fko-01
Get-FileHash "$h\app.code-workspace"
Get-Content  "$h\app.code-workspace" -Raw    # record VERBATIM into your report
Get-Content  "$h\.gitignore" -Raw            # record VERBATIM
```

Settings preconditions — identical to Run 3 **C1**, re-checked here because Run 3 will have written
some of them:

| Setting | Required |
|---|---|
| `aprodaAldc.bcquality.path` | **cleared** (Run 3 may have set it — briefing §5) |
| `terminal.integrated.env.*.BCQUALITY_HOME` | **cleared on all three platforms** |
| `aprodaAldc.source.mode` / `source.forkPath` | `localFork` / the fork under test |
| `aprodaAldc.devRoot` | `c:\_EphemeralWorkspace` — still deliberately wrong |
| Installed extension | `aprodaag.aproda-aldc-0.1.8-test.7` |

| ID | Criterion |
|---|---|
| **D1** | Clean tree on `temp-fko-01`; no `.github/`, no `aldc.yaml`, no `.external/`, no Aproda block in `.gitignore` |
| **D2** | `app.code-workspace` and `.gitignore` recorded verbatim and hashed |
| **D3** | Settings preconditions hold. **Any leaked `bcquality.path` or `BCQUALITY_HOME`: stop and report** — it would short-circuit the rung this run exists to test |
| **D4** | Exactly **one** BCQuality clone on the machine (re-run Run 3's Phase-0 enumeration); count recorded |

---

## Phase 1 — Apply Toolkit into an empty repository

Open `app.code-workspace` and run **`Aproda ALDC: Apply Toolkit to Project (per Repo)`**.
Start a stopwatch. **Keep the Aproda ALDC output channel open and capture it in full** — Phase 2 reads
it as evidence.

| ID | Criterion |
|---|---|
| **D5** | The command resolves the target repository to `HEKS Base` **even though the repo root is not a workspace folder** and no `aldc.yaml` exists to identify it. If a quick-pick appeared, record **every** entry it offered — and whether the BCQuality clone was among them |
| **D6** | Completes without blocking on a dialog; duration recorded |
| **D7** | `.github/` created with the toolkit (`agents/`, `skills/`, `prompts/`, `instructions/`, `tools/aproda-sync/`, `copilot-instructions.md`) |
| **D8** | `.github/aldc.yaml` present, non-empty, and contains `toolkitRoot: ".github"` |
| **D9** | **No `aldc.yaml` at the repository root.** A first init must land on the T-33 shape directly, never on the old one and then migrate |
| **D10** | `.external/` created **with `README.md`** |
| **D11** | `.gitignore`: the pre-existing content is **preserved verbatim**, and an `Aproda ALDC Tool BEGIN/END` block is appended containing `/.github/aldc.yaml` and `/.external/bcquality/` |

### The workspace file

| ID | Criterion |
|---|---|
| **D12** | `folders` still contains `source` and `test`, and now also `.external` (and `.github`, if the seed mounts it — record what it actually did) |
| **D13** | `settings.cSpell.words` (`ASFI`, `HEKS`) survived |
| **D14** | The pre-existing `files.exclude` (`**/*.dep.app`, `**/rad.json`) survived **and was not extended with anything BCQuality-related** — T-30: BCQuality uses `search.exclude` + `files.watcherExclude` only, **never** `files.exclude` |
| **D15** | The pre-existing `search.exclude` entries survived, and `bcquality/**` was added to `search.exclude` **and** `files.watcherExclude` |
| **D16** | `app.code-workspace.bak` exists and is **byte-identical to the content recorded in D2** — including the trailing comma. If the backup differs, that is a blocker; note whether the trailing comma is what broke it |

---

## Phase 2 — BCQuality on a first init (the point of this run)

**Do nothing yet.** First observe what Apply Toolkit did on its own.

At this moment nothing can resolve: the clone is not mounted here, `BCQUALITY_HOME` is cleared,
`bcquality.path` is empty, `devRoot` is wrong, and `.external/bcquality` does not exist yet. The
declared `aldc.yaml → home` points at a junction nothing has created. **That is a legitimate outcome,
not a failure** — record it as such.

What must **not** have happened is a silent clone.

| ID | Criterion |
|---|---|
| **D17** | **No new clone anywhere.** Re-run the enumeration from D4 — identical result, same single clone, same file count |
| **D18** | The output log shows the post-bootstrap BCQuality step running and reaching a decision. Quote the lines. Expected: no verified root, therefore no junction. **A stack trace — or complete silence, where D19 then also shows no junction — is a finding**: silence is the shape the broken first repair had |
| **D19** | `.external\bcquality` does **not** exist yet (nothing resolved), and `.external\` is otherwise intact with its `README.md` |
| **D20** | Run `Aproda ALDC: Show BCQuality Status`. It lists **all five rungs** with a per-candidate verdict, shows the **declared** home (`.external/bcquality`) next to the **resolved** root (none), and does not pretend anything is active |

### Now trigger the install — with the wrong `devRoot` still in place

| ID | Criterion |
|---|---|
| **D21** | Run **`Install / Update BCQuality`**. A modal confirmation **must** appear, naming `c:\_EphemeralWorkspace\BCQuality-Aproda` — the wrong path the stale `devRoot` produces. **This is the real-world form of the B-23 trap**: the fix does not make the wrong path right, it makes it visible before anything is written |
| **D22** | **Cancel it (press Esc).** Afterwards: that directory was not created, no `git clone` ran, `bcquality.path` was not written, and no junction appeared |

### Then point it at the real clone

1. Set Global `aprodaAldc.bcquality.path` to `c:\_EphemeralWorkspace\Florian Köll\BCQuality-Aproda`.
2. Run **`Install / Update BCQuality`** again.

| ID | Criterion |
|---|---|
| **D23** | **No prompt.** The target now exists and is a git root, so it must take the update path silently |
| **D24** | `.external\bcquality` now exists and its **target** is the real clone — assert `(Get-Item '<repo>\.external\bcquality' -Force).Target`, **not** its existence. *This is the criterion Run 2 lacked, which is why a duplicate clone passed a 30-point list* |
| **D25** | Global `terminal.integrated.env.windows.BCQUALITY_HOME` set to the real clone; **`linux` and `osx` carry no `BCQUALITY_HOME`** |
| **D26** | Still exactly **one** clone on the machine |

---

## Phase 3 — Does the knowledge layer actually work here

| ID | Criterion |
|---|---|
| **D27** | `#bcquality` can `read` `skills/entry.md` through the junction, and `list` a directory under it |
| **D28** | `grep_search` for a string that exists **only** inside BCQuality returns no hits from this workspace — the exclusion holds on this workspace file too, which it could not on the old sibling-root layout (B-9) |
| **D29** | `#aldcConfiguration` returns the resolved configuration from `.github/aldc.yaml`, including the BCQuality values. **Note explicitly** whether `read_file .github/aldc.yaml` also works — that depends on whether `.github` was mounted as a workspace folder (D12), and the repo root is not one |
| **D30** | `Aproda ALDC: Validate Installation` runs and reports on the freshly initialized project. Record its verdict — a first init is the cleanest input this check will ever get |

### Added after run 4 — the defects it uncovered (B-28 … B-31)

| ID | Criterion |
|---|---|
| **D31** | **No setting holds a path inside a repository.** After D23, `aprodaAldc.bcquality.path` and `BCQUALITY_HOME` must both be the **real clone**, never `<repo>\.external\bcquality`, and they must agree with each other (B-28) |
| **D32** | `Get-Item '<repo>\.external\bcquality' -Force` succeeds — no `ELOOP` — and its `Target` is the real clone, not itself (B-28) |
| **D33** | **Reopen the window.** No "ALDC is not installed" / "do you want to initialize" prompt appears on a project that was just initialized (B-29) |
| **D34** | D30 produces an actual verdict, not `spawn npm ENOENT` (B-30) |
| **D35** | The log states what the BCQuality step decided at every stage — including the legitimate "resolved nothing, no link" case in D18. **Silence is a finding** (B-31). **Read the channel immediately after Apply Toolkit** — no window reload, no VSIX install, no extension-host restart in between; each of those recreates the channel and destroys the evidence. Run 4.2's silence is unexplained and may be exactly this |

---

## Phase 4 — Report and leave alone

Do not reset, do not commit, do not push. Report the final `git status --short` so the maintainer can
decide what to keep.

---

## Report

Per `e2e-00-briefing.md` §4. Additionally answer these four in one sentence each, because they are what
the run exists for:

1. Did a first init land directly on the T-33 shape, with **no** root `aldc.yaml`? (D9)
2. Did the post-bootstrap BCQuality step run, and what did it decide? (D18)
3. Did any step create a second clone? (D17, D26)
4. What exactly does the junction point at? (D24)
