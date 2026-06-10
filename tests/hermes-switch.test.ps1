$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "hermes-switch.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-switch-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Invoke-HermesSwitch {
    param([hashtable]$Parameters)

    $output = & $scriptPath @Parameters 2>&1
    return ($output | Out-String)
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    if (-not $Text.Contains($Needle)) {
        throw "$Message`nExpected to find: $Needle`nActual:`n$Text"
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    if ($Text.Contains($Needle)) {
        throw "$Message`nDid not expect to find: $Needle`nActual:`n$Text"
    }
}

try {
    $configA = Join-Path $tempRoot "config-a.yaml"
    $configB = Join-Path $tempRoot "config-b.yaml"

    @"
model:
  default: old-model
  provider: auto
  base_url: https://old.example/v1
providers: {}
agent:
  max_turns: 60
"@ | Set-Content -LiteralPath $configA -Encoding UTF8

    @"
model:
  provider: custom:existing
  default: another-old-model
  base_url: https://another.example/v1
  api_mode: chat_completions
  api_key: old-key
providers:
  custom:existing:
    name: Existing
    model: another-old-model
custom_providers:
  - name: keep-me
    base_url: https://keep.example/v1
    api_key: keep-key
    api_mode: chat_completions
"@ | Set-Content -LiteralPath $configB -Encoding UTF8

    Invoke-HermesSwitch -Parameters @{
        Key = "test-relay-key"
        Model = "gpt-5.5"
        BaseUrl = "https://relay.example/v1/"
        ReasoningEffort = "xhigh"
        ConfigPath = @($configA, $configB)
        NoPrompt = $true
    } | Out-Null

    foreach ($config in @($configA, $configB)) {
        $content = Get-Content -LiteralPath $config -Raw -Encoding UTF8

        Assert-Contains $content "provider: custom:relay" "Provider was not set to named custom provider."
        Assert-Contains $content "default: gpt-5.5" "Model was not set."
        Assert-Contains $content "custom_providers:" "custom_providers block was not written."
        Assert-Contains $content "  - name: relay" "Named custom provider entry was not written."
        Assert-Contains $content "    base_url: https://relay.example/v1" "Base URL was not normalized in custom provider."
        Assert-Contains $content "    api_key: test-relay-key" "API key was not written in custom provider."
        Assert-Contains $content "      reasoning_effort: xhigh" "custom provider reasoning effort was not written."
        Assert-Contains $content "  reasoning_effort: xhigh" "agent.reasoning_effort was not set."

        if ($config -eq $configB) {
            Assert-Contains $content "custom:existing:" "Unrelated providers block should be preserved."
            Assert-Contains $content "  - name: keep-me" "Unrelated custom provider should be preserved."
            Assert-NotContains $content "providers: {}" "Script should not wipe existing providers to an empty map."
        }

        $backup = Get-ChildItem -LiteralPath (Split-Path -Parent $config) -Filter ((Split-Path -Leaf $config) + ".bak-*") | Select-Object -First 1
        if (-not $backup) {
            throw "Backup file was not created for $config"
        }
    }

    $status = Invoke-HermesSwitch -Parameters @{ ConfigPath = @($configA); Status = $true }
    Assert-Contains $status "model   : gpt-5.5" "Status did not show model."
    Assert-Contains $status "base_url: https://relay.example/v1" "Status did not show base_url."
    Assert-Contains $status "api_key : <set>" "Status did not redact key."
    Assert-NotContains $status "test-relay-key" "Status leaked the API key."

    Invoke-HermesSwitch -Parameters @{
        Key = "rotated-relay-key"
        ConfigPath = @($configA)
        NoPrompt = $true
    } | Out-Null
    $rotated = Get-Content -LiteralPath $configA -Raw -Encoding UTF8
    Assert-Contains $rotated "provider: custom:relay" "Existing named provider was not preserved during key rotation."
    Assert-Contains $rotated "default: gpt-5.5" "Existing model was not inferred during key rotation."
    Assert-Contains $rotated "base_url: https://relay.example/v1" "Existing base URL was not inferred during key rotation."
    Assert-Contains $rotated "api_key: rotated-relay-key" "New API key was not written during key rotation."
    $relayEntryCount = ([regex]::Matches($rotated, "(?m)^[ \t]*-[ \t]+name:[ \t]*relay[ \t]*$")).Count
    if ($relayEntryCount -ne 1) {
        throw "Expected exactly one relay custom provider entry after key rotation, found $relayEntryCount. Actual:`n$rotated"
    }

    $beforeDryRun = Get-Content -LiteralPath $configA -Raw -Encoding UTF8
    $dryRun = Invoke-HermesSwitch -Parameters @{
        Key = "dry-run-key"
        Model = "gpt-4.1"
        BaseUrl = "https://dry.example/v1"
        ReasoningEffort = "none"
        ConfigPath = @($configA)
        NoPrompt = $true
        DryRun = $true
    }
    $afterDryRun = Get-Content -LiteralPath $configA -Raw -Encoding UTF8
    if ($beforeDryRun -ne $afterDryRun) {
        throw "DryRun modified the config file."
    }
    Assert-Contains $dryRun "reasoning_effort: none" "DryRun did not show the requested reasoning effort."
    Assert-NotContains $dryRun "dry-run-key" "DryRun leaked the API key."

    $configC = Join-Path $tempRoot "config-c.yaml"
    @"
model:
  default: anthropic/claude-opus-4.6
  provider: auto
  base_url: https://openrouter.ai/api/v1
providers: {}
"@ | Set-Content -LiteralPath $configC -Encoding UTF8

    $failedAsExpected = $false
    try {
        Invoke-HermesSwitch -Parameters @{
            Key = "test-relay-key"
            ConfigPath = @($configC)
            NoPrompt = $true
        } | Out-Null
    }
    catch {
        if ($_.Exception.Message -match "Model is required") {
            $failedAsExpected = $true
        }
    }

    if (-not $failedAsExpected) {
        throw "Script should require -Model/-BaseUrl when no custom provider exists."
    }

    Write-Host "hermes-switch tests passed"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
