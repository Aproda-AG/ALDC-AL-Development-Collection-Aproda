# altool fixtures (E-010 phase 4b, `S-4b.*`)

Ten fixtures are real, scrubbed captures (L-4b.12, 2026-11-03/04); the other nine are still provisional
reconstructions of the documented fields (`AlMcpE010Phase0Evidence.md`).

| Fixture | Status |
|---|---|
| `help-main-de.txt`, `help-runtests-de.txt` | captured (L-4b.12, 2026-11-03) |
| `publish-success.txt`, `publish-duplicate.txt`, `publish-connection-refused.txt` | captured (L-4b.12, 2026-11-03) |
| `runtests-green-complete.txt`, `runtests-red-testrunfailed.txt`, `runtests-wrong-port.txt` | captured (L-4b.12, 2026-11-03) |
| `publish-auth.txt`, `runtests-auth-failure.txt` | captured (L-4b.12, 2026-11-04) |
| `help-main-en.txt`, `help-main-no-runtests.txt`, `help-runtests-en.txt`, `help-runtests-no-testgroups.txt` | provisional |
| `publish-rejected-sync.txt`, `publish-rejected-compile-422.txt` | provisional |
| `runtests-noise-chunklength.txt`, `runtests-truncated-first-group.txt`, `runtests-nontest-only.txt` | provisional |

Capture format: `# exit code: N; timedOut: False; durationMs: M`, `--- stdout ---`, the text, `--- stderr ---`, the text.
Exit codes the tests assume: publish success 0, every other fixture 1; `runtests` green/truncated/non-test 0,
red/auth/wrong port 1.

No fixture contains a credential, a host name of a real target, or an authorization header.
