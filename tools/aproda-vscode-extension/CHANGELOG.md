# Changelog

## 0.1.7

- Adds a scope suffix to each Get Started walkthrough step title ("one-time setup" vs. "per repository") so users can tell workstation-level setup apart from per-project actions at a glance.

## 0.1.6

- Expands the Get Started walkthrough with contextual descriptions for every step (what happens, prerequisites, one-time vs. per-project) instead of bare command links.
- Adds a Validate Installation step to the walkthrough, with a troubleshooting pointer to Environment Diagnostics and Show Log.
- Notes that the Azure CLI setup step has no linked command and must be marked done manually.
- Fixes a "Check for Extension Updates" sign-in/retry failure (`Invalid combination of options: forceNewSession, createIfNone`) by no longer combining both mutually exclusive authentication options.
- Fixes an extension update install failure (`No Servers`) by installing the downloaded VSIX from a `file:` URI instead of one derived from `globalStorageUri`, which VS Code's extension installer rejected for install.

## 0.1.5

- Clones the managed toolkit cache in full instead of as a partial (`--filter=blob:none`) clone, removing the on-demand blob fetch that failed with `RPC failed; HTTP 400 ... fatal: expected 'packfile'` on networks that mangle Git's smart-HTTP negotiation.
- Detects an existing partial-clone cache and rebuilds it as a full clone automatically, with no manual Git configuration required on any developer's machine.

## 0.1.4

- Retries a failed extension update check by forcing a fresh VS Code GitHub authentication session, then automatically re-running the check, instead of only opening a Git-credential terminal.

## 0.1.3

- Opens the Aproda ALDC walkthrough directly from the first-run notification and applies the toolkit from its second step.
- Uses Toolkit terminology consistently in user-facing commands, messages, setup, and onboarding documentation.
- Restores the initial setup notification after resetting extension-owned local data without resetting VS Code walkthrough progress.
- Packages local VSIX artifacts with the extension version in their file name.

## 0.1.2

- Activates after VS Code startup so first-run setup is offered in repositories without existing ALDC or AL files.
- Offers to initialize an AL project containing `app.json` but no `aldc.yaml`, with a per-repository dismissal option.

## 0.1.1

- Adds a GitHub sign-in retry path for private repository update checks.
- Uses the fixed Aproda repository as the trust root for extension self-updates.
- Publishes versioned VSIX assets and uses CI-gated release tags with GitHub Environment approval.

## 0.1.0

- Initial internal VSIX release with managed layer source, project apply and preview, version checks, configuration tool, setup wizard, central BCQuality management, and onboarding walkthrough.
- Checks tagged internal VSIX releases and, after explicit confirmation and GitHub authentication, installs newer releases and offers a VS Code reload.