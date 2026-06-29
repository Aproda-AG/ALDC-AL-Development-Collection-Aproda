---
applyTo: "**/test/**/*.al"
description: "AL Testing & Project Structure Rules - Ensure proper project organization and test implementation"
---

# AL Testing — Micro Rules

Hard rules for test files. Test patterns (given/when/then, libraries, asserts) and examples in `skill-testing`.

1. **Do not generate tests unless explicitly requested** ("create tests for…", "add test coverage", "write unit tests…"). Default focus is on the App.
2. **Strict AL-Go separation**: tests only in the `Test/` project, never in `App/`. The `app.json` of Test depends on App's; App's does **not** depend on Test.
3. **Test/ structure mirrors App/**: if `App/src/Sales/Invoice/...` exists, tests live in `Test/src/Sales/Invoice/...`. Shared helpers in `Test/src/Common/`.
4. **Codeunit with `Subtype = Test`** and standard dependencies: `Codeunit Assert`, `Library - <Module>` (Sales, Inventory, Manufacturing, ERM, Random). Create master/document data **only** via these MS libraries — never hand-build records. Hand-written `CreateX` helpers are allowed solely to set custom fields on top of a library-created record, or when no library covers the table (note it).
5. **Test method names in Given/When/Then pattern**: `GivenX_WhenY_ThenZ`. Each test ends with one or more explicit `Assert.*` calls.
6. **Mandatory skill**: writing or changing tests REQUIRES loading `skill-testing` (read its `SKILL.md`) first — it owns the library reference + symbol-discovery recipe. Proof token `🧠 skill-testing·MSLibraries` is required when tests change.
