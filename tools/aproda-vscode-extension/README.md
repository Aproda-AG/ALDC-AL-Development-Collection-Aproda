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