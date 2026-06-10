# Security Policy

## Reporting a Vulnerability

Please open a GitHub issue if you find a security problem in this tool.

Do not include real API keys, private URLs, or private config files in public issues.

## Secret Handling

Hermes Switch never intentionally prints API keys. It writes the API key into Hermes' `config.yaml` because Hermes needs it to call your relay.

Backups created by this tool may contain old API keys. Store, delete, and share backup files carefully.
