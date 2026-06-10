# Hermes Switch

Hermes Switch is a small PowerShell utility for **Hermes Desktop** users who connect through a custom OpenAI-compatible relay, proxy, or New API endpoint.

It writes the custom URL, API key, model name, and reasoning effort into Hermes' `config.yaml`, creates backups, and keeps API keys out of terminal output.

## Features

- Interactive URL, key, and model input
- One-command non-interactive mode
- Automatic detection of common Hermes Desktop config paths
- Timestamped backups before writing
- API key redaction in terminal output
- Reasoning effort values: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`
- Writes both `agent.reasoning_effort` and `custom_providers.extra_body.reasoning_effort`
- Uses named custom providers such as `custom:relay`
- `-Status` mode for inspection
- `-DryRun` mode for previewing changes

## Quick Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1
```

The script asks for:

- API key
- model name, for example `gpt-5.5`
- base URL, for example `https://example.com/v1`

Restart Hermes Desktop or start a new Hermes session after the script finishes.

## One Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort high `
  -NoPrompt
```

For maximum reasoning effort:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort xhigh `
  -NoPrompt
```

## Double Click on Windows

Double-click:

```text
hermes-switch.cmd
```

## Status

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 -Status
```

The real key is not printed. The output shows `<set>` or `<empty>`.

## Dry Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort high `
  -NoPrompt `
  -DryRun
```

## Generated Config

Hermes Switch writes a named custom provider:

```yaml
model:
  provider: custom:relay
  default: gpt-5.5
  api_mode: chat_completions

custom_providers:
  - name: relay
    base_url: https://example.com/v1
    api_key: YOUR_API_KEY
    model: gpt-5.5
    api_mode: chat_completions
    extra_body:
      reasoning_effort: high

agent:
  reasoning_effort: high
```

This matters because many OpenAI-compatible relays only honor the request-body `reasoning_effort`. Updating only `agent.reasoning_effort` may change the Hermes session label while the relay still behaves like `medium`.

## Config Paths

The script checks common config locations:

- `%APPDATA%\cn.org.hermesagent.desktop\runtime\hermes-home\config.yaml`
- `%LOCALAPPDATA%\hermes\config.yaml`
- `%USERPROFILE%\.hermes\config.yaml`
- `~/.hermes/config.yaml`
- macOS/Linux-style Hermes Desktop runtime paths, when present

You can pass a custom path with `-ConfigPath`.

## Testing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\hermes-switch.test.ps1
```

## Security

- Do not commit real API keys.
- Terminal output redacts keys.
- `config.yaml` and backup files may contain keys. Treat them as secrets.

## License

MIT
