<#
.SYNOPSIS
Switch Hermes Desktop custom OpenAI-compatible endpoint settings.

.DESCRIPTION
Updates Hermes config.yaml files for users who run Hermes Desktop through a
custom relay, proxy, or OpenAI-compatible endpoint. The script asks for an API
key when omitted, redacts secrets in output, creates timestamped backups, and
can inject provider-specific request body fields such as reasoning_effort.

.EXAMPLE
.\hermes-switch.ps1 -BaseUrl https://relay.example/v1 -Model gpt-5.5

.EXAMPLE
.\hermes-switch.ps1 -Key $env:API_KEY -BaseUrl https://relay.example/v1 -Model gpt-5.5 -ReasoningEffort xhigh -NoPrompt

.EXAMPLE
.\hermes-switch.ps1 -Status
#>
[CmdletBinding()]
param(
    [string]$Key,
    [string]$Model,
    [string]$BaseUrl,
    [ValidateSet("none", "minimal", "low", "medium", "high", "xhigh")]
    [string]$ReasoningEffort = "high",
    [string]$ProviderName = "relay",
    [string[]]$ConfigPath,
    [switch]$Status,
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-DefaultConfigPaths {
    $paths = New-Object System.Collections.Generic.List[string]

    if ($env:APPDATA) {
        $paths.Add((Join-Path $env:APPDATA "cn.org.hermesagent.desktop\runtime\hermes-home\config.yaml"))
    }
    if ($env:LOCALAPPDATA) {
        $paths.Add((Join-Path $env:LOCALAPPDATA "hermes\config.yaml"))
    }
    if ($env:USERPROFILE) {
        $paths.Add((Join-Path $env:USERPROFILE ".hermes\config.yaml"))
    }
    if ($HOME) {
        $paths.Add((Join-Path $HOME ".hermes/config.yaml"))
        $paths.Add((Join-Path $HOME "Library/Application Support/cn.org.hermesagent.desktop/runtime/hermes-home/config.yaml"))
        $paths.Add((Join-Path $HOME ".config/cn.org.hermesagent.desktop/runtime/hermes-home/config.yaml"))
    }

    $paths | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique
}

function Get-TopLevelBlock {
    param(
        [string]$Content,
        [string]$Name
    )

    $escaped = [regex]::Escape($Name)
    $pattern = '(?m)^' + $escaped + '[ \t]*:\r?\n(?:^[ \t]+.*(?:\r?\n|$)|^[ \t]*$(?:\r?\n|$))*'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        return $match.Value
    }

    return ""
}

function Get-TopLevelBlockMatch {
    param(
        [string]$Content,
        [string]$Name
    )

    $escaped = [regex]::Escape($Name)
    $pattern = '(?m)^' + $escaped + '[ \t]*:\r?\n(?:^[ \t]+.*(?:\r?\n|$)|^[ \t]*$(?:\r?\n|$))*'
    return [regex]::Match($Content, $pattern)
}

function Get-ModelValue {
    param(
        [string]$Block,
        [string]$Name
    )

    if (-not $Block) {
        return ""
    }

    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Block, "(?m)^[ \t]+$escaped[ \t]*:[ \t]*(.*?)[ \t]*$")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups[1].Value.Trim(" `"'")
}

function Get-ConfigValue {
    param(
        [string]$Content,
        [string]$BlockName,
        [string]$ValueName
    )

    $block = Get-TopLevelBlock -Content $Content -Name $BlockName
    return Get-ModelValue -Block $block -Name $ValueName
}

function Get-CustomProviderEntryBlock {
    param(
        [string]$CustomProvidersBlock,
        [string]$CustomProviderName
    )

    if (-not $CustomProvidersBlock) {
        return ""
    }

    $namePattern = [regex]::Escape($CustomProviderName)
    $entryPattern = '(?ms)^[ \t]*-[ \t]+name:[ \t]*[''"]?' + $namePattern + '[''"]?[ \t]*(?:\r?\n(?!(?:[ \t]*-[ \t]+name:)|\z).*)*'
    $match = [regex]::Match($CustomProvidersBlock, $entryPattern)
    if ($match.Success) {
        return $match.Value
    }

    return ""
}

function Get-NestedYamlValue {
    param(
        [string]$Block,
        [string]$Name
    )

    if (-not $Block) {
        return ""
    }

    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Block, "(?m)^[ \t]+$escaped[ \t]*:[ \t]*(.*?)[ \t]*$")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups[1].Value.Trim(" `"'")
}

function Get-CustomProviderValue {
    param(
        [string]$Content,
        [string]$CustomProviderName,
        [string]$ValueName
    )

    $block = Get-TopLevelBlock -Content $Content -Name "custom_providers"
    $entry = Get-CustomProviderEntryBlock -CustomProvidersBlock $block -CustomProviderName $CustomProviderName
    return Get-NestedYamlValue -Block $entry -Name $ValueName
}

function Get-ConfigHint {
    param([string[]]$Paths)

    $fallback = @{
        Model = ""
        BaseUrl = ""
        IsCustom = $false
    }

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $block = Get-TopLevelBlock -Content $content -Name "model"
        if (-not $block) {
            continue
        }

        $provider = Get-ModelValue -Block $block -Name "provider"
        $model = Get-ModelValue -Block $block -Name "default"
        $baseUrl = Get-ModelValue -Block $block -Name "base_url"
        $isCustom = $provider -like "custom*"

        if ($provider -like "custom:*") {
            $providerName = ($provider -replace "^custom:", "").Trim()
            $customBaseUrl = Get-CustomProviderValue -Content $content -CustomProviderName $providerName -ValueName "base_url"
            if ($customBaseUrl) {
                $baseUrl = $customBaseUrl
            }
        }

        if (-not $fallback.Model -and $model) {
            $fallback.Model = $model
        }
        if (-not $fallback.BaseUrl -and $baseUrl) {
            $fallback.BaseUrl = $baseUrl
        }

        if ($isCustom -and $model -and $baseUrl) {
            return @{
                Model = $model
                BaseUrl = $baseUrl
                IsCustom = $true
            }
        }
    }

    return $fallback
}

function Read-PlainSecret {
    param([string]$Prompt)

    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Normalize-BaseUrl {
    param([string]$Url)

    $trimmed = ($Url -as [string]).Trim()
    if (-not $trimmed) {
        return ""
    }

    return $trimmed.TrimEnd("/")
}

function Normalize-ProviderName {
    param([string]$Name)

    $trimmed = ($Name -as [string]).Trim()
    if (-not $trimmed) {
        return "relay"
    }
    return ($trimmed -replace "[^A-Za-z0-9_.-]", "-")
}

function New-ModelBlock {
    param(
        [string]$ModelName,
        [string]$CustomProviderName
    )

    return @"
model:
  provider: custom:$CustomProviderName
  default: $ModelName
  api_mode: chat_completions

"@
}

function New-CustomProviderEntry {
    param(
        [string]$ModelName,
        [string]$RelayBaseUrl,
        [string]$ApiKey,
        [string]$Effort,
        [string]$CustomProviderName
    )

    return @"
  - name: $CustomProviderName
    base_url: $RelayBaseUrl
    api_key: $ApiKey
    model: $ModelName
    api_mode: chat_completions
    extra_body:
      reasoning_effort: $Effort
"@
}

function Upsert-CustomProviderEntry {
    param(
        [string]$Content,
        [string]$Entry,
        [string]$CustomProviderName
    )

    $blockMatch = Get-TopLevelBlockMatch -Content $Content -Name "custom_providers"
    if (-not $blockMatch.Success) {
        return $Content.TrimEnd() + [Environment]::NewLine + "custom_providers:" + [Environment]::NewLine + $Entry + [Environment]::NewLine
    }

    $block = $blockMatch.Value
    $namePattern = [regex]::Escape($CustomProviderName)
    $entryPattern = '(?ms)^[ \t]*-[ \t]+name:[ \t]*[''"]?' + $namePattern + '[''"]?[ \t]*(?:\r?\n(?!(?:[ \t]*-[ \t]+name:)|\z).*)*'
    $newBlock = [regex]::Replace($block, $entryPattern, "", 1).TrimEnd()
    if (-not $newBlock.Trim()) {
        $newBlock = "custom_providers:"
    }
    $newBlock = $newBlock + [Environment]::NewLine + $Entry + [Environment]::NewLine

    return $Content.Remove($blockMatch.Index, $blockMatch.Length).Insert($blockMatch.Index, $newBlock)
}

function Set-AgentReasoningEffort {
    param(
        [string]$Content,
        [string]$Effort
    )

    if ($Content -match '(?m)^agent:\s*$') {
        $agentMatch = [regex]::Match($Content, '(?m)^agent:\r?\n(?:^[ \t]+.*(?:\r?\n|$)|^[ \t]*$(?:\r?\n|$))*')
        if ($agentMatch.Success) {
            $agentBlock = $agentMatch.Value
            if ($agentBlock -match '(?m)^[ \t]+reasoning_effort[ \t]*:') {
                $newAgentBlock = [regex]::Replace($agentBlock, '(?m)^([ \t]+reasoning_effort[ \t]*:).*$', "`$1 $Effort", 1)
            }
            else {
                $newAgentBlock = $agentBlock.TrimEnd() + [Environment]::NewLine + "  reasoning_effort: $Effort" + [Environment]::NewLine
            }
            return $Content.Remove($agentMatch.Index, $agentMatch.Length).Insert($agentMatch.Index, $newAgentBlock)
        }
    }

    return $Content + [Environment]::NewLine + "agent:" + [Environment]::NewLine + "  reasoning_effort: $Effort" + [Environment]::NewLine
}

function Update-HermesConfig {
    param(
        [string]$Path,
        [string]$ModelName,
        [string]$RelayBaseUrl,
        [string]$ApiKey,
        [string]$Effort,
        [string]$CustomProviderName,
        [switch]$Preview
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Skip missing config: $Path"
        return $false
    }

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $newBlock = New-ModelBlock -ModelName $ModelName -CustomProviderName $CustomProviderName
    $customEntry = New-CustomProviderEntry -ModelName $ModelName -RelayBaseUrl $RelayBaseUrl -ApiKey $ApiKey -Effort $Effort -CustomProviderName $CustomProviderName
    $match = Get-TopLevelBlockMatch -Content $content -Name "model"

    if ($match.Success) {
        $updated = $content.Remove($match.Index, $match.Length).Insert($match.Index, $newBlock)
    }
    else {
        $updated = $newBlock + [Environment]::NewLine + $content
    }

    $updated = Upsert-CustomProviderEntry -Content $updated -Entry $customEntry -CustomProviderName $CustomProviderName
    $updated = Set-AgentReasoningEffort -Content $updated -Effort $Effort

    if ($Preview) {
        Write-Output "[dry-run] Would update: $Path"
        return $true
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.bak-$timestamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
    Write-Output "Updated: $Path"
    Write-Output "Backup : $backupPath"
    return $true
}

function Show-HermesStatus {
    param([string[]]$Paths)

    $found = $false
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $found = $true
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $provider = Get-ConfigValue -Content $content -BlockName "model" -ValueName "provider"
        $modelName = Get-ConfigValue -Content $content -BlockName "model" -ValueName "default"
        $relayBaseUrl = Get-ConfigValue -Content $content -BlockName "model" -ValueName "base_url"
        $apiMode = Get-ConfigValue -Content $content -BlockName "model" -ValueName "api_mode"
        $apiKey = Get-ConfigValue -Content $content -BlockName "model" -ValueName "api_key"
        if ($provider -like "custom:*") {
            $providerName = ($provider -replace "^custom:", "").Trim()
            $customBaseUrl = Get-CustomProviderValue -Content $content -CustomProviderName $providerName -ValueName "base_url"
            $customApiMode = Get-CustomProviderValue -Content $content -CustomProviderName $providerName -ValueName "api_mode"
            $customApiKey = Get-CustomProviderValue -Content $content -CustomProviderName $providerName -ValueName "api_key"
            if ($customBaseUrl) {
                $relayBaseUrl = $customBaseUrl
            }
            if ($customApiMode) {
                $apiMode = $customApiMode
            }
            if ($customApiKey) {
                $apiKey = $customApiKey
            }
        }
        $effort = Get-ConfigValue -Content $content -BlockName "agent" -ValueName "reasoning_effort"

        Write-Output "Path    : $path"
        Write-Output "provider: $provider"
        Write-Output "model   : $modelName"
        Write-Output "base_url: $relayBaseUrl"
        Write-Output "api_mode: $apiMode"
        Write-Output ("api_key : " + ($(if ($apiKey) { "<set>" } else { "<empty>" })))
        Write-Output "reasoning_effort: $effort"
        Write-Output ""
    }

    if (-not $found) {
        throw "No Hermes config files found. Pass -ConfigPath or start Hermes Desktop once to create config.yaml."
    }
}

if (-not $ConfigPath -or $ConfigPath.Count -eq 0) {
    $ConfigPath = Get-DefaultConfigPaths
}

$existingPaths = @($ConfigPath | Where-Object { Test-Path -LiteralPath $_ })
if ($existingPaths.Count -eq 0) {
    throw "No Hermes config files found. Pass -ConfigPath or start Hermes Desktop once to create config.yaml."
}

if ($Status) {
    Show-HermesStatus -Paths $ConfigPath
    return
}

$hint = Get-ConfigHint -Paths $ConfigPath

if (-not $Model -and $hint.IsCustom) {
    $Model = $hint.Model
}
if (-not $BaseUrl -and $hint.IsCustom) {
    $BaseUrl = $hint.BaseUrl
}

if (-not $Key) {
    if ($NoPrompt) {
        throw "-Key is required when -NoPrompt is used."
    }
    $Key = Read-PlainSecret -Prompt "Paste new Hermes relay API key"
}

if (-not $Model) {
    if ($NoPrompt) {
        throw "-Model is required because no existing model could be inferred."
    }
    $Model = Read-Host -Prompt "Model name"
}

if (-not $BaseUrl) {
    if ($NoPrompt) {
        throw "-BaseUrl is required because no existing base_url could be inferred."
    }
    $BaseUrl = Read-Host -Prompt "Base URL, usually ending with /v1"
}

$Model = $Model.Trim()
$BaseUrl = Normalize-BaseUrl -Url $BaseUrl
$Key = $Key.Trim()
$ProviderName = Normalize-ProviderName -Name $ProviderName

if (-not $Key) {
    throw "API key cannot be empty."
}
if (-not $Model) {
    throw "Model cannot be empty."
}
if (-not $BaseUrl) {
    throw "Base URL cannot be empty."
}
if ($BaseUrl -notmatch "^https?://") {
    throw "Base URL must start with http:// or https://"
}

$updatedCount = 0
foreach ($path in $ConfigPath) {
    if (Update-HermesConfig -Path $path -ModelName $Model -RelayBaseUrl $BaseUrl -ApiKey $Key -Effort $ReasoningEffort -CustomProviderName $ProviderName -Preview:$DryRun) {
        $updatedCount++
    }
}

if ($updatedCount -eq 0) {
    throw "No config files were updated."
}

Write-Output ""
Write-Output "Hermes model config is now set to:"
Write-Output "  provider: custom"
Write-Output "  model   : $Model"
Write-Output "  base_url: $BaseUrl"
Write-Output "  reasoning_effort: $ReasoningEffort"
Write-Output "  custom_provider: $ProviderName"
Write-Output "  api_key : <hidden>"
Write-Output ""
if ($DryRun) {
    Write-Output "Dry run only. No files were changed."
}
else {
    Write-Output "Restart Hermes Desktop or start a new Hermes session for the change to take effect."
}
