# Hermes Switch

一个给 Hermes Desktop 用户使用的自定义中转站配置切换工具。它会把你的 OpenAI-compatible URL、API key、模型名和 reasoning effort 写入 Hermes 的 `config.yaml`，并自动备份旧配置。

This is a small PowerShell utility for Hermes Desktop users who connect through a custom OpenAI-compatible relay, proxy, or New API endpoint.

## Features

- Interactive mode for URL, key, and model input
- One-command non-interactive mode for scripts
- Updates common Hermes Desktop config locations automatically
- Creates timestamped backups before writing
- Redacts API keys in terminal output
- Supports `none`, `minimal`, `low`, `medium`, `high`, and `xhigh` reasoning effort
- Writes both `agent.reasoning_effort` and `custom_providers.extra_body.reasoning_effort`
- Supports `-DryRun` preview and `-Status` inspection

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Hermes Desktop already launched at least once
- A custom OpenAI-compatible endpoint, usually ending with `/v1`

## Quick Start

Download or clone this repo, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1
```

The script will ask for:

- API key
- model name, for example `gpt-5.5`
- base URL, for example `https://example.com/v1`

After it finishes, restart Hermes Desktop or start a new Hermes session.

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

## Double Click

On Windows, double-click:

```text
hermes-switch.cmd
```

This opens the interactive PowerShell script and pauses at the end so you can read the result.

## Check Current Config

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 -Status
```

The key is never printed. You will see `<set>` or `<empty>`.

## Preview Without Writing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort high `
  -NoPrompt `
  -DryRun
```

## Config Paths

By default, the script checks common Hermes locations:

- `%APPDATA%\cn.org.hermesagent.desktop\runtime\hermes-home\config.yaml`
- `%LOCALAPPDATA%\hermes\config.yaml`
- `%USERPROFILE%\.hermes\config.yaml`
- `~/.hermes/config.yaml`
- macOS/Linux-style Hermes Desktop runtime paths, when present

You can target a file manually:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -ConfigPath "C:\path\to\config.yaml" `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -NoPrompt
```

## What It Writes

The main generated block looks like this:

```yaml
model:
  provider: custom
  default: gpt-5.5
  base_url: https://example.com/v1
  api_mode: chat_completions
  api_key: YOUR_API_KEY
providers: {}
fallback_providers: []
custom_providers:
  - name: relay
    base_url: https://example.com/v1
    model: gpt-5.5
    api_mode: chat_completions
    extra_body:
      reasoning_effort: high

agent:
  reasoning_effort: high
```

The `custom_providers.extra_body.reasoning_effort` line matters for many OpenAI-compatible relays because Hermes' generic `custom` provider may not otherwise forward the reasoning effort to your relay.

## Restore a Backup

Every write creates a backup next to the config:

```text
config.yaml.bak-YYYYMMDD-HHMMSS
```

To restore, close Hermes Desktop and copy the backup over `config.yaml`.

## Testing

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\hermes-switch.test.ps1
```

## Security Notes

- Do not commit real API keys.
- Prefer passing keys interactively when possible.
- Terminal output redacts keys, but `config.yaml` necessarily stores the key because Hermes needs it.
- Backup files also contain the key that existed at the time of backup. Treat them as secrets.

## License

MIT
