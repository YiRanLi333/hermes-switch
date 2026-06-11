# Hermes Switch

Hermes Switch 是一个给 **Hermes Desktop** 用户使用的自定义中转站配置切换工具。它可以把你的 OpenAI-compatible URL、API Key、模型名和 reasoning effort 写入 Hermes 的 `config.yaml`，适合经常更换中转站 Key、模型或接口地址的用户。

[English documentation](docs/README.en.md)

## 功能

- 交互式输入 URL、Key、模型名
- 支持命令行一键切换，方便写进脚本
- 自动查找常见 Hermes Desktop 配置路径
- 写入前自动生成时间戳备份
- 终端输出永远隐藏 API Key
- 支持 `none`、`minimal`、`low`、`medium`、`high`、`xhigh`
- 同时写入 `agent.reasoning_effort` 和 `custom_providers.extra_body.reasoning_effort`
- 使用命名 custom provider，例如 `custom:relay`
- 支持 `-Status` 查看当前配置
- 支持 `-DryRun` 预览，不改文件

## 快速开始

在 PowerShell 里先下载仓库，再进入仓库目录：

```powershell
cd $env:USERPROFILE\Desktop
git clone https://github.com/YiRanLi333/hermes-switch.git
cd hermes-switch
```

然后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1
```

注意：`.\hermes-switch.ps1` 里的 `.\` 表示“当前目录”。如果你还在 `C:\WINDOWS\system32` 或别的目录，PowerShell 会找不到这个脚本。

脚本会依次询问：

- API Key
- 模型名，例如 `gpt-5.5`
- Base URL，例如 `https://example.com/v1`

运行完成后，重启 Hermes Desktop，或者新建一个 Hermes 会话。

## 不安装 Git，直接下载脚本

如果电脑没有 Git，也可以只下载脚本：

```powershell
mkdir "$env:USERPROFILE\Desktop\hermes-switch" -Force
cd "$env:USERPROFILE\Desktop\hermes-switch"
Invoke-WebRequest "https://raw.githubusercontent.com/YiRanLi333/hermes-switch/main/hermes-switch.ps1" -OutFile ".\hermes-switch.ps1"
Invoke-WebRequest "https://raw.githubusercontent.com/YiRanLi333/hermes-switch/main/hermes-switch.cmd" -OutFile ".\hermes-switch.cmd"
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1
```

## Windows 双击使用

直接双击：

```text
hermes-switch.cmd
```

它会打开交互式 PowerShell，并在结束时暂停，方便你看结果。

## 一条命令切换

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort high `
  -NoPrompt
```

如果要使用最高 reasoning effort：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort xhigh `
  -NoPrompt
```

## 查看当前配置

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 -Status
```

输出会显示 `api_key : <set>` 或 `api_key : <empty>`，不会打印真实 Key。

## 预览但不写入

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -ReasoningEffort high `
  -NoPrompt `
  -DryRun
```

## 默认配置路径

脚本会自动检查这些位置：

- `%APPDATA%\cn.org.hermesagent.desktop\runtime\hermes-home\config.yaml`
- `%LOCALAPPDATA%\hermes\config.yaml`
- `%USERPROFILE%\.hermes\config.yaml`
- `~/.hermes/config.yaml`
- macOS/Linux 风格的 Hermes Desktop runtime 路径，如果存在

也可以手动指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\hermes-switch.ps1 `
  -ConfigPath "C:\path\to\config.yaml" `
  -Key "YOUR_API_KEY" `
  -BaseUrl "https://example.com/v1" `
  -Model "gpt-5.5" `
  -NoPrompt
```

## 写入的配置格式

Hermes Switch 使用命名 custom provider。核心结构如下：

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

这样写的好处是：

- `model.provider` 明确指向 `custom:relay`
- URL 和 Key 都在对应的 `custom_providers` 条目里
- 不会依赖旧的裸 `provider: custom` 推断逻辑
- `extra_body.reasoning_effort` 会随请求发给 OpenAI-compatible 中转站

很多中转站只看请求体里的 `reasoning_effort`，只改 `agent.reasoning_effort` 可能会让 Hermes 界面显示 high/xhigh，但实际请求仍然像 medium。这个工具会两边都写。

## 备份和恢复

每次写入都会在原配置旁边生成备份：

```text
config.yaml.bak-YYYYMMDD-HHMMSS
```

恢复方法：

1. 关闭 Hermes Desktop
2. 找到对应 `.bak-*` 文件
3. 复制覆盖回 `config.yaml`
4. 重新打开 Hermes Desktop

## 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\hermes-switch.test.ps1
```

## 安全提醒

- 不要把真实 API Key 提交到 GitHub
- 终端输出会隐藏 Key，但 `config.yaml` 必须保存 Key，Hermes 才能调用你的中转站
- 自动生成的备份文件也可能包含旧 Key，请当作敏感文件处理
- 如果你的 Key 经常变化，直接重新运行本工具即可

## 许可证

MIT
