# Upstream provenance

This tool vendors the minimal runtime subset of `rvanbekkum/ps-xliff-sync` needed
to synchronize generated Business Central XLIFF files and validate translations.

- Repository: <https://github.com/rvanbekkum/ps-xliff-sync>
- Version: `1.10.0.0`
- Pinned commit: `3f9413d9642360e58312847e68c7cb45906d8014`
- License: MIT; see `vendor/LICENSE`.

Vendored runtime files:

- `vendor/XliffSync/Model/XlfDocument.ps1`
- `vendor/XliffSync/Public/Sync-XliffTranslations.ps1`
- `vendor/XliffSync/Public/Test-XliffTranslations.ps1`

The upstream module loader is deliberately excluded because it uses path-based
dot-sourcing, which is blocked by this estate's Software Restriction Policy.

## Local additive patches

`vendor/XliffSync/Model/XlfDocument.ps1` carries three local patches on top of the pinned
upstream commit.

1. `XlfTranslationState`, `GetState`, and `UpdateStateAttributes` support
   `needs-review-translation` and `needs-l10n`. No upstream enum value or state mapping
   was changed.
2. `useSelfClosingTags` defaults to `$true`. Upstream defaults it to `$false`, which expands
   every empty element on save. Since Business Central and PoEdit both emit `<note … />`,
   that rewrote roughly 3500 notes in a real customer file and buried the actual change in
   the diff. `Sync-XliffTranslations` assigns the value from its own switch, so the wrapper
   passes `-useSelfClosingTags` there as well.
3. `SaveToFilePath` normalizes the written file to Business Central's serialization: .NET's
   `XmlWriter` emits `<x />` and a byte order mark, Business Central emits `<x/>` and none.
   Without this, every empty element and the first line differ on every run. The rewrite is
   skipped when the output already matches, so an unchanged file is not touched. On a real
   customer file this reduced a synchronization diff from about 7200 lines to 126 — the
   20 units that actually changed.

All three patches are guarded by tests; re-vendoring without re-applying them fails the suite.