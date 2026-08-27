# Changelog

## 0.1.1

- Adds a GitHub sign-in retry path for private repository update checks.
- Uses the fixed Aproda repository as the trust root for extension self-updates.
- Publishes versioned VSIX assets and uses CI-gated release tags with GitHub Environment approval.

## 0.1.0

- Initial internal VSIX release with managed layer source, project apply and preview, version checks, configuration tool, setup wizard, central BCQuality management, and onboarding walkthrough.
- Checks tagged internal VSIX releases and, after explicit confirmation and GitHub authentication, installs newer releases and offers a VS Code reload.