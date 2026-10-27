# altool fixtures (E-010 phase 4b, `S-4b.*`)

**ALL FIXTURES ARE PROVISIONAL — replace with the scrubbed captures from L-4b.12 (OS-1).**

The exact raw text of `altool` (18.1.43) was not recorded in Phase 0; only the observed *fields* and
*semantics* are documented (`AlMcpE010Phase0Evidence.md`: Q-13a/b/c, Q-9, Q-10, Q-1). These files are minimal
reconstructions that follow that documentation. Their field layout (nesting of `data`, names of the aggregate
counters, wording of the publish messages, the help layout) is an assumption until replaced.

| Fixture | Documented in Phase 0 | Assumed |
|---|---|---|
| `help-main-*.txt`, `help-runtests-*.txt` | command and option names `compile`, `publishapp`, `runtests`, `--testgroups`; German help text ("Nutzung", "Optionen") | layout, descriptions, German wording of the other lines |
| `publish-success.txt` | exit 0 | the message |
| `publish-duplicate.txt` | exit 1, HTTP `422 UnprocessableEntity`, `duplicate package ID` (Q-13c) | surrounding wording |
| `publish-rejected-compile-422.txt` | HTTP `422 UnprocessableEntity`, `Extension compilation failed`, `AL1024` missing dependency (live finding 2026-10-23) | surrounding wording |
| `publish-auth.txt` | `UserNotAuthenticatedException` (Q-1, Q-10) | surrounding wording, exit 1 |
| `publish-rejected-sync.txt` | the engine rule *sync / schema message = Rejected* | the message |
| `publish-connection-refused.txt` | `ConnectionFailed` code name (Q-20) | the message |
| `runtests-green-complete.txt` | 25 records for 59010 + 59013, 13 + 10 test methods and two blank-method completion records, `A task was canceled.` before the JSON (Q-13a) | field names `data.total/passed/failed/skipped`, status wording `Passed` |
| `runtests-noise-chunklength.txt` | `Index was out of range ... chunkLength` before a successful JSON (Q-13a, Fkh) | record content |
| `runtests-truncated-first-group.txt` | only 59010 executed, `succeeded: true`, `data.success: true`, then `A task was canceled.` (Q-13a) | record content |
| `runtests-nontest-only.txt` | `total: 0`, `results: []`, `succeeded: true` (Q-13b) | — |
| `runtests-red-testrunfailed.txt` | exit 1, `succeeded: false`, `errorDetails.code: TestRunFailed`, error text and AL call stack in `output`, blank-method duplicate (11 passed, 2 failed) (Q-9) | call stack wording |
| `runtests-auth-failure.txt` | `UserNotAuthenticatedException` (Q-10) | where the text sits in `errorDetails` |
| `runtests-wrong-port.txt` | exit 1, `succeeded: false`, `errorDetails.code: UnknownError`, `retryable: true` (Q-13b) | message |

Exit codes the tests assume: publish success 0, every other fixture 1; `runtests` green/truncated/non-test 0,
red/auth/wrong port 1.

No fixture contains a credential, a host name of a real target, or an authorization header.
