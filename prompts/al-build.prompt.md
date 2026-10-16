---
agent: agent
model: GPT-5.6 Terra (copilot)
description: 'Build, package, and deploy AL extensions to Business Central environments.'
tools: [vscode, execute, read, agent, edit, search, web, ms-dynamics-smb.al/al_build, ms-dynamics-smb.al/al_downloadsymbols, ms-dynamics-smb.al/al_publish, ms-dynamics-smb.al/al_symbolsearch, ms-dynamics-smb.al/al_get_diagnostics, todo]

---

# Build and Deploy AL Extension

Your goal is to build and deploy the AL extension for `${input:DeploymentType}` environment.
## Select Deployment Strategy
Based on #codebase select the appropriate deployment strategy
Ask and confirm with the user before proceeding.
## Deployment Types

Based on the deployment type, use the appropriate strategy:

### Development Environment
1. **Build**: Use `al_build` to compile the project
2. **Review**: Present build results for human approval
3. **Deploy**: Use `al_publish` with `type: "incremental"` (RAD) for rapid iteration (requires approval)
4. **Verify**: Check for any compilation errors

### Testing Environment
1. **Build**: Use `al_build` with full validation — it also produces the `.app` package
2. **Review**: Present package details for human approval
3. **Deploy**: Use `al_publish` to deploy with debugging enabled (requires approval)
4. **Test**: Ensure all unit tests pass

### Production Environment 
1. **Build**: Use `al_build` with strict validation — the produced `.app` is the release package
2. **Validation**: Verify package integrity and dependencies
3. **Documentation**: Generate deployment checklist and present for review
4. **Human Gate**: **MANDATORY** - Manual approval required before any production action
   - **Note**: Automated deployment to production is intentionally disabled as safeguard
   - All production changes require explicit human authorization

### Existing Package Deployment
- Use `al_publish` with `skipbuild: true` when deploying a pre-built .app file
- Verify package compatibility with target environment

### Full Dependency Package
- Use `al_publish` with `fulldependencytree: true` to build and publish all project dependencies in order
- Useful for multi-app workspaces

## Error Handling

Monitor the output for:
- Compilation errors
- Dependency conflicts
- Publishing failures
- Permission issues

## Post-Deployment Verification

After deployment:
1. Verify extension appears in Extension Management
2. Check all functionality works as expected
3. Validate permissions are correctly applied
4. Monitor for any runtime errors