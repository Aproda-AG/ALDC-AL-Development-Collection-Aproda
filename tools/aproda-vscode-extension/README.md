# Aproda ALDC for Visual Studio Code

Internal Visual Studio Code tooling for Aproda ALDC projects. The extension guides configuration, applies the managed Aproda layer, manages a central BCQuality clone, and exposes the authoritative ALDC configuration to Copilot.

## Commands

- **Configure Settings** configures the developer root, layer source, channel, and startup checks.
- **Preview Update Changes** calculates layer changes without modifying the project.
- **Apply Layer to Project** initializes or updates the current repository.
- **Install / Update BCQuality** maintains the central external BCQuality-Aproda clone.
- **Check for Updates** compares the project's installed layer version with the latest tagged release.
- **Reset Layer Cache and Settings** removes extension-owned local data only; project files and local forks remain untouched.

Use **Open Getting Started** or the **Get Started with Aproda ALDC** walkthrough after installation.

## Development

Run `npm test` to compile and run focused tests. Run `npm run package` to produce `dist/aproda-aldc.vsix`.

## Internal Installation

Download `aproda-aldc.vsix` from the internal GitHub release and install it with VS Code's **Extensions: Install from VSIX...** command, or run:

```powershell
code --install-extension .\aproda-aldc.vsix
```

Reinstall a newer VSIX from the same command. The extension does not update itself.

## Release

Update `package.json` and `CHANGELOG.md`, then create and push a matching tag such as `vscode-ext/v0.1.0`. The release workflow verifies the tag, runs tests, packages the VSIX, and attaches it to the GitHub release.