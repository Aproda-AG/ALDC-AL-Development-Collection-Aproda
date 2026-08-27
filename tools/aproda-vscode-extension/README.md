# Aproda ALDC for Visual Studio Code

Internal Visual Studio Code toolkit for Aproda ALDC projects. The extension guides configuration, applies the managed Aproda toolkit, manages a central BCQuality clone, and exposes the authoritative ALDC configuration to Copilot.

## Commands

- **Open Get Started** opens the native VS Code walkthrough for first-time setup.
- **Configure Settings** configures the developer root, toolkit source, channel, BCQuality location, and toolkit update checks.
- **Preview Update Changes** calculates toolkit changes without modifying the project.
- **Apply Toolkit to Project** initializes or updates the current repository.
- **Install / Update BCQuality** maintains the central external BCQuality-Aproda clone.
- **Check for Updates** compares the project's installed toolkit version with the latest tagged release.
- **Reset Toolkit Cache and Settings** removes extension-owned local data only; project files and local forks remain untouched.

Use **Open Onboarding Guide** for the external documentation or **Open Get Started** for the native VS Code walkthrough.

## Development

Run `npm test` to compile and run focused tests. Run `npm run package` to produce `dist/aproda-aldc-<version>.vsix`.

## Internal Installation

Download the versioned release asset, for example `aproda-aldc-0.1.0.vsix`, from the internal GitHub release and install it with VS Code's **Extensions: Install from VSIX...** command, or run:

```powershell
code --install-extension .\aproda-aldc-0.1.0.vsix
```

The extension checks for a newer internal release at startup and through **Check for Extension Updates**. Selecting **Update Extension** signs in to GitHub when needed, downloads the release VSIX, installs it, and offers to reload VS Code.

## Release

Update `package.json` and `CHANGELOG.md`, validate the candidate, then merge it to `aproda`. The release workflow validates the version, runs tests, packages `aproda-aldc-<semver>.vsix`, and waits for approval in the `aproda-vscode-extension-release` Environment. After approval, CI creates the matching `vscode-ext/v<semver>` tag and GitHub Release. Do not create or push VSIX release tags manually.