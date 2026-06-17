# Windows installer

这个目录提供一个**增强版** Windows 安装脚本，特点是：

1. 先安装 **Node.js LTS**
2. 再使用 **npm 全局安装** CLI
3. 再写入各自的 auth/config
4. 尝试安装 **Codex Desktop**
5. 自动做 **安装后自检**
6. 输出 **日志、警告、失败汇总、状态表**

不是临时 portable 环境，也不是一次性 shell 注入环境。

## 安装对象

- Codex CLI: `@openai/codex`
- Claude Code: `@anthropic-ai/claude-code`
- Gemini CLI: `@google/gemini-cli`
- Codex Desktop: Microsoft Store / `winget`

## 用法

### 交互式

```powershell
powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1
```

### 非交互式

```powershell
powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1 `
  -NonInteractive `
  -CodexApiKey <OPENAI_API_KEY> `
  -ClaudeApiKey <ANTHROPIC_API_KEY> `
  -GeminiApiKey <GEMINI_API_KEY>
```

### 只写配置，不安装

```powershell
powershell -ExecutionPolicy Bypass -File .\windows-installer\install.ps1 `
  -ConfigOnly `
  -NonInteractive `
  -CodexApiKey <OPENAI_API_KEY>
```

## 默认行为（LEUNG 模板）

- 若未检测到 `node`/`npm`，脚本会尝试：
  - `winget install --id OpenJS.NodeJS.LTS`
- CLI 安装默认：
  - `npm install -g @openai/codex`
  - `npm install -g @anthropic-ai/claude-code`
  - `npm install -g @google/gemini-cli`
- Codex Desktop 默认尝试：
  - `winget install --id 9PLM9XGG6VKS --source msstore`
- 安装后默认执行自检：
  - 检查 `node` / `npm`
  - 检查 `codex` / `claude` / `gemini`
  - 检查配置文件是否存在

## 写入的配置位置

- Codex: `%USERPROFILE%\.codex\config.toml` 和 `%USERPROFILE%\.codex\auth.json`
- Claude: `%USERPROFILE%\.claude\settings.json`
- Gemini: `%USERPROFILE%\.gemini\settings.json` 和 `%USERPROFILE%\.gemini\.env`

## 日志位置

- `%USERPROFILE%\.leung\logs\install-YYYYMMDD-HHMMSS.log`

## 可选参数

- `-SkipDesktop`: 跳过 Codex Desktop
- `-ConfigOnly`: 只写配置
- `-SkipNodeInstall`: 缺少 Node.js 时不自动装
- `-ForceNpm`: Codex CLI 也强制走 npm，不先尝试 winget
- `-SkipSelfCheck`: 跳过安装后自检
- `-CodexBaseUrl` / `-ClaudeBaseUrl` / `-GeminiBaseUrl`: 自定义 API 地址
- `-CodexModel` / `-ClaudeModel` / `-GeminiModel`: 自定义默认模型

## 增强点

相比前一个精简版，这个版本新增：

- 安装日志落盘
- PowerShell 执行策略自动修正（CurrentUser -> RemoteSigned）
- 安装状态表
- 警告汇总
- 失败汇总
- 安装后自检

## 建议的后续增强

如果继续做更完整的发布版，下一步建议加：

- GUI 包装
- 离线 bundle
- 配置模板切换
- 多 provider 预设
- 更细的桌面端安装检测


## GUI 用法

可以直接双击：

```bat
windows-installer\Launch-GUI.bat
```

或者运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows-installer\gui.ps1
```

GUI 版支持：

- 输入 3 个 API Key
- 自定义 URL / 模型
- 跳过 Desktop
- Config only
- Force npm
- Skip self-check
- 实时查看安装输出日志

## 更强自检内容

增强后的自检会额外验证：

- `Get-Command node/npm/codex/claude/gemini` 是否可解析
- `--version` 是否能正常返回
- 关键配置文件是否存在
- 关键配置内容是否写入成功
- Codex Desktop 是否能被本地检测到（尽力检查）


## LEUNG 模板默认值

当前脚本已统一改为参考 `win-installer` 中的 LEUNG 模板：

- Codex Base URL: `https://api.leung315.site/v1`
- Claude Base URL: `https://api.leung315.site`
- Gemini Base URL: `https://api.leung315.site`
- Codex Model: `gpt-5.4`
- Claude Model: `claude-sonnet-4-5`
- Gemini Model: `gemini-2.5-pro`

并且配置写入逻辑也对齐 LEUNG 模板：

- Codex 使用 `model_provider = "leung"`
- Claude 写入 LEUNG 风格 `settings.json`
- Gemini 写入 LEUNG 风格 `settings.json + .env`


## GUI 新增功能

现在 GUI 额外支持：

- 系统状态检测：`winget` / `node` / `npm` / `codex` / `claude` / `gemini` / `Codex Desktop`
- 配置状态检测：Codex / Claude / Gemini 配置文件与日志目录
- 刷新状态按钮
- 组件勾选安装：
  - Codex CLI
  - Claude Code
  - Gemini CLI
  - Codex Desktop
- 一键 `Select All` / `Clear All`
- `Open Logs` 按钮直接打开 `%USERPROFILE%\.leung\logs`

## CLI 新增组件参数

安装脚本新增可选参数：

- `-InstallCodex`
- `-InstallClaude`
- `-InstallGemini`
- `-InstallDesktop`

如果一个都不传，则默认全部安装。
