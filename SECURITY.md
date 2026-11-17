# Security Policy

## Supported versions

Only the latest release of Blueprint Conversion Utility receives security fixes. Use **Help > Check for Updates...** to confirm you are current.

## Reporting a vulnerability

Please report vulnerabilities privately. Do not open a public issue.

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the problem, the steps to reproduce it, and the impact.

You can expect an acknowledgement within a few days. Fixes ship as a normal signed and notarized release, and the advisory is published once a fixed version is available.

## What to include

- The BCU version and macOS version
- What you did and what you expected to happen
- Relevant log excerpts

Remove Jamf client IDs, client secrets, tokens, and environment details before sharing anything.

## Scope notes

BCU stores each Jamf Platform client secret in the macOS Keychain. Reports about credential handling, update integrity, installer signing, or unintended changes to Jamf environments are especially welcome.
