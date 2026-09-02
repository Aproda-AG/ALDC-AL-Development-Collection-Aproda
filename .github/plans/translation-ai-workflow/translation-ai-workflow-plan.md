# Plan: Token-Efficient AI XLIFF Workflow

**Status:** Implemented, including approved D-2 agent and PR evidence integration
**Continues in:** `translation-architecture-context.md` (evidence, constraints, principles) and
`translation-architecture-options.md` (target architecture, staged delivery, decision log). This
document describes the delivered baseline only.

## Goal

Automate deterministic XLIFF work locally and give AI only the missing, contextualized
translation units. AI returns a minimal response; PowerShell validates every response before
writing it into the target XLIFF file.

## Scope

- Extend `tools/aproda-ps-xliffsync/Invoke-AprodaBuildXliffSync.ps1`.
- Extend `skills/skill-translate/SKILL.md` with the Aproda workflow and response contract.
- Keep the existing MIT-licensed minimal XliffSync vendor set unchanged.
- Defer the local translation-memory concept to `E-005`.
- Integrate the approved translation gates in `al-developer`, `al-conductor`, and `al-pr-prepare`.

## Tool Design

The wrapper exposes four explicit actions, using `de-CH` by default:

| Action | Purpose | Writes target XLIFF |
|---|---|---|
| `Sync` | Build unless skipped, synchronize `*.g.xlf` to the target language, and show issue statistics. | Yes |
| `ExportOpen` | Export missing translation units to a compact JSON batch. | No |
| `Apply` | Read a compact AI response and atomically apply valid translations. | Yes |
| `Validate` | Report missing units, units requiring review, and technical validation problems. | May update XLIFF Sync review states/notes |

### Batch Contract

`ExportOpen` writes a batch outside the repository by default. The batch lists target XLIFF
paths once; every item refers to its file by index and contains a stable key, XLIFF unit ID,
source text, source hash, generator/developer context, placeholders, and an optional XLIFF
length limit when present.

AI receives only this batch. Its response uses:

```json
{
  "schemaVersion": 1,
  "batchId": "...",
  "translations": [
    { "key": "...", "target": "Freigeben" }
  ]
}
```

It does not repeat source text, context, rules, or unchanged entries. `Apply` verifies the
batch ID, unique keys, current source hash, non-empty targets, placeholders, and discoverable
XLIFF length limits before modifying any target file. Any invalid response prevents all writes.

## Skill Contract

`skill-translate` remains the single translation skill. It specifies the AI translation and
review process; the PowerShell tool performs the deterministic operations. The skill will
require this sequence:

1. `Sync` after translation-relevant AL changes.
2. `ExportOpen` only for missing translations.
3. Translate a bounded JSON batch using the compact response contract.
4. `Apply`, then `Validate`.
5. Use strict validation before a handoff that claims translations are complete.

Semantic terminology, context judgment, and manual review remain AI/human work. Technical
validation does not claim to prove terminology or every AL `MaxLength` value; it enforces a
length only when it is represented in the XLIFF unit metadata.

## Agent Integration

| Later touch point | Planned behavior | Why it belongs there |
|---|---|---|
| `al-developer` | Loads `skill-translate`; invokes the sequence only when an app with `TranslationFile` enabled changed labels, captions, tooltips, or translation files. | Keeps normal AL changes free of XLIFF writes. |
| `al-conductor` phase implementation | Passes `skill-translate` as a required hint for translation-relevant work and requires evidence of `Sync`/`Apply`/`Validate`. | Makes translation work explicit without making every phase pay for it. |
| `al-conductor` completion | Runs final `Validate -FailOnIssues` before entering `review` when the requirement changed translations. | Translation completeness is a delivery property, not a compile property. |
| `al-pr-prepare` | Consumes recorded validation evidence only; does not sync, export, translate, or mutate XLIFF files. | PR preparation remains delivery-only and deterministic. |

Implemented as approved in-place agent/process changes under D-2. Foundation mirrors remain
unchanged because the Aproda XLIFF tool is distributed through the overlay only.

## Validation

- Parse the PowerShell wrapper.
- Smoke-test `Sync`, `ExportOpen`, `Apply`, and `Validate` using synthetic XLIFF fixtures.
- Confirm malformed, stale, duplicate, and placeholder-invalid responses make no target-file
  changes.
- Run `npm test` and `git diff --check`.