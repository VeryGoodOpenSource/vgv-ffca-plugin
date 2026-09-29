# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 0.1.x   | Yes       |

Only the latest release on `main` receives security updates.

## Reporting a Vulnerability

### GitHub Private Vulnerability Reporting (preferred)

Report vulnerabilities through [GitHub's private vulnerability reporting](https://github.com/VeryGoodOpenSource/vgv-ffca-plugin/security/advisories/new).

### Email

Send an email to `tools@verygood.ventures` with a `[SECURITY]` subject prefix.

### What to Include

- A description of the vulnerability
- Steps to reproduce the issue
- Affected files or components

### Response Timeline

- **Acknowledgment:** within 5 business days
- **Assessment:** within 10 business days
- **Notification:** you will be notified when a fix is released

## Scope

The plugin ships skills, a hook, an agent, and a Dart validator script. The security-relevant surface areas are:

### Skill, Agent, and Reference Files (`skills/*/SKILL.md`, `agents/*.md`, `references/`)

- Insecure code examples that developers may copy into production
- Outdated or misleading guidance
- Recommendations that contradict current best practices

### Hook and Validator Scripts (`hooks/`, `scripts/`)

- Command injection vulnerabilities
- Unsafe path handling
- Unintended code execution

### Plugin Manifest & MCP Config (`.claude-plugin/plugin.json`, `.mcp.json`)

- Excessive permissions
- Exploitable MCP server definitions

## Recognition

We are happy to acknowledge reporters in the fix PR upon request.
