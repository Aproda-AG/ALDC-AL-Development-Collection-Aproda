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

## Local additive patch

`vendor/XliffSync/Model/XlfDocument.ps1` has a local additive patch on top of
the pinned upstream commit. `XlfTranslationState`, `GetState`, and
`UpdateStateAttributes` support `needs-review-translation` and `needs-l10n`.
No upstream enum value or state mapping was changed.