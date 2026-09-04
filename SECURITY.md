# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository when
available. Do not publish credentials, private hostnames, access tokens, model
inputs, or server logs containing sensitive data in a public issue.

## Deployment assumptions

- The SGLang endpoint has no authentication in this recipe.
- It binds to `127.0.0.1` by default and should be reached through SSH port
  forwarding or another authenticated private transport.
- `--trust-remote-code` is enabled only for the pinned and hash-verified model
  snapshot. Review changes before using another revision.
- The scripts never require an API token in a command-line argument. If a
  backend needs credentials, provide them through that backend's documented
  credential store or environment mechanism and keep them out of logs.
